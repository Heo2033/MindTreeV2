//! Управление жизненным циклом встроенного Node-сервера (sidecar).
//!
//! Один процесс приложения = один локальный сервер. Rust выбирает свободный
//! порт, генерирует одноразовый токен авторизации, запускает бандл
//! `server/sidecar` через bundled `node`, ждёт готовности (health-poll),
//! сторожит процесс и корректно гасит его при выходе.

use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use rand::RngCore;
use tauri::{AppHandle, Emitter, Manager, State};

/// Максимальное время ожидания готовности сервера после запуска.
const SERVER_START_TIMEOUT_MS: u64 = 10_000;
/// Частота опроса /api/health при старте.
const HEALTH_POLL_MS: u64 = 150;
/// Лимит серверного лога в байтах: при превышении текущий файл уходит в .1.
const SERVER_LOG_MAX_BYTES: u64 = 1 << 20;

pub struct ServerState {
    inner: Arc<Mutex<Option<RunningServer>>>,
}

pub struct RunningServer {
    pub port: u16,
    token: String,
    child: Child,
}

#[derive(serde::Serialize, Clone)]
pub struct ServerStatusDto {
    pub running: bool,
    pub port: Option<u16>,
    pub pid: Option<u32>,
}

#[derive(serde::Serialize)]
pub struct ServerInfoDto {
    pub port: u16,
    pub token: String,
}

impl ServerState {
    pub fn new() -> Self {
        ServerState { inner: Arc::new(Mutex::new(None)) }
    }
}

impl Default for ServerState {
    fn default() -> Self {
        Self::new()
    }
}

/// Берём произвольный свободный порт на loopback. Слушатель тут же
/// закрывается — микро-гонка на порт при локальном запуске приемлема.
fn free_port() -> Result<u16, String> {
    let listener = TcpListener::bind(("127.0.0.1", 0)).map_err(|e| e.to_string())?;
    Ok(listener.local_addr().map_err(|e| e.to_string())?.port())
}

/// Случайный токен доступа к локальному серверу. Передаётся процессу через env
/// и выдаётся фронтенду одноразовой командой — угадать его невозможно.
fn generate_token() -> String {
    let mut bytes = [0u8; 24];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Каталог бандла сервера (dist/index.js + node_modules).
/// В dev — локальная папка `server/sidecar`, в релизе — упакованный ресурс.
#[cfg_attr(debug_assertions, allow(unused_variables))]
fn resolve_server_dir(app: &AppHandle) -> Result<PathBuf, String> {
    if let Ok(dir) = std::env::var("MINDTREE_SERVER_DIR") {
        return Ok(PathBuf::from(dir));
    }
    #[cfg(debug_assertions)]
    {
        Ok(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../server/sidecar"))
    }
    #[cfg(not(debug_assertions))]
    {
        let base = app.path().resource_dir().map_err(|e| e.to_string())?;
        // В собранном виде ресурсы лежат рядом с exe (не установлено) —
        // или под resources/ (установлено через MSI/NSIS).
        for candidate in [
            base.join("server-sidecar"),
            base.join("resources/server-sidecar"),
        ] {
            if candidate.join("dist/index.js").exists() {
                return Ok(candidate);
            }
        }
        Ok(base.join("server-sidecar"))
    }
}

/// Исполняемый файл Node, запечённый в sidecar (`bin/node[.exe]`).
/// Оверрайд `MINDTREE_NODE` — для отладки на другом runtime.
fn resolve_node_bin(_app: &AppHandle, server_dir: &Path) -> Result<PathBuf, String> {
    if let Ok(bin) = std::env::var("MINDTREE_NODE") {
        return Ok(PathBuf::from(bin));
    }
    let name = if cfg!(windows) { "node.exe" } else { "node" };
    Ok(server_dir.join("bin").join(name))
}

/// Запускает сервер, если он ещё не запущен, и возвращает его порт.
/// После спавна ждёт, пока /api/health не ответит 200 (wait-ready), иначе
/// возвращает ошибку и убивает процесс, чтобы фронтенд не висел вслепую.
pub fn ensure_server(app: &AppHandle, state: &State<ServerState>) -> Result<u16, String> {
    let mut guard = state
        .inner
        .lock()
        .map_err(|_| "server state lock poisoned".to_string())?;
    if let Some(running) = guard.as_ref() {
        return Ok(running.port);
    }

    let server_dir = plain_path(&resolve_server_dir(app)?);
    let entry = server_dir.join("dist/index.js");
    let node = plain_path(&resolve_node_bin(app, &server_dir)?);
    let app_data = plain_path(&app.path().app_data_dir().map_err(|e| e.to_string())?);

    log_err(
        app,
        &format!(
            "[server] init dir={} node={}",
            server_dir.display(),
            node.display()
        ),
    );
    if !entry.exists() {
        let msg = format!("server bundle not found at {}", entry.display());
        log_err(app, &format!("[server] ERROR {msg}"));
        return Err(msg);
    }
    if node.is_absolute() && !node.exists() {
        let msg = format!("node binary not found at {}", node.display());
        log_err(app, &format!("[server] ERROR {msg}"));
        return Err(msg);
    }
    std::fs::create_dir_all(&app_data).map_err(|e| e.to_string())?;

    let port = free_port()?;
    let token = generate_token();
    let child = Command::new(&node)
        .arg(&entry)
        .current_dir(&server_dir)
        .env("PORT", port.to_string())
        .env("HOST", "127.0.0.1")
        .env("DB_PATH", app_data.join("mindtree.db"))
        .env(
            "MINDTREE_SERVER_CONFIG",
            app_data.join("runtime-config.json"),
        )
        .env("MINDTREE_AUTH_TOKEN", &token)
        .spawn()
        .map_err(|e| format!("spawn node ({}) failed: {e}", node.display()))?;
    log_err(
        app,
        &format!("[server] spawned pid={} port={port}", child.id()),
    );

    if let Err(e) = wait_until_healthy(app, port) {
        let _ = child_kill(child);
        log_err(app, &format!("[server] ERROR {e}"));
        return Err(e);
    }

    let inner = state.inner.clone();
    let handle = app.clone();
    let running = RunningServer { port, token, child };
    let status_desc = ServerStatusDto {
        running: true,
        port: Some(port),
        pid: Some(running.child.id()),
    };
    *guard = Some(running);
    drop(guard);

    spawn_watchdog(handle, inner, status_desc);
    log_err(app, &format!("[server] ready on http://127.0.0.1:{port}"));
    Ok(port)
}

/// Опрашивает /api/health, пока сервер не ответит 200 или не выйдет таймаут.
fn wait_until_healthy(app: &AppHandle, port: u16) -> Result<(), String> {
    let deadline = Instant::now() + Duration::from_millis(SERVER_START_TIMEOUT_MS);
    loop {
        if http_get_health(port, Duration::from_millis(800)) {
            log_err(app, &format!("[server] health ok on port {port}"));
            return Ok(());
        }
        if Instant::now() >= deadline {
            return Err(format!(
                "server did not become healthy within {SERVER_START_TIMEOUT_MS}ms"
            ));
        }
        std::thread::sleep(Duration::from_millis(HEALTH_POLL_MS));
    }
}

/// Фоновый поток: следит за child-процессом. Когда node падает, состояние
/// помечается running:false и фронтенду уходит событие — индикатор статуса
/// больше не врёт, а следующий `get_server_port` перезапустит сервер.
fn spawn_watchdog(
    app: AppHandle,
    inner: Arc<Mutex<Option<RunningServer>>>,
    status: ServerStatusDto,
) {
    std::thread::spawn(move || {
        loop {
            let mut guard = match inner.lock() {
                Ok(g) => g,
                Err(_) => return,
            };
            let exited = match guard.as_mut() {
                Some(running) => running.child.try_wait().ok().flatten().is_some(),
                // Сервер уже остановлен/перезапущен — сторож больше не нужен.
                None => return,
            };
            if exited {
                let port = status.port;
                let pid = status.pid;
                *guard = None;
                drop(guard);
                log_err(
                    &app,
                    &format!("[server] process exited unexpectedly (pid={pid:?} port={port:?})"),
                );
                let _ = app.emit(
                    "server://status",
                    ServerStatusDto {
                        running: false,
                        port: None,
                        pid: None,
                    },
                );
                return;
            }
            drop(guard);
            std::thread::sleep(Duration::from_millis(1000));
        }
    });
}

/// Гасит встроенный сервер. Сначала пробует штатный /api/shutdown (с токеном)
/// и ждёт выхода процесса; если сервер не отвечает — жёсткий kill.
pub fn stop_server(app: &AppHandle, state: &State<ServerState>) -> Result<(), String> {
    let mut guard = state
        .inner
        .lock()
        .map_err(|_| "server state lock poisoned".to_string())?;
    let Some(running) = guard.take() else {
        return Ok(());
    };
    let mut child = running.child;
    let token = running.token.clone();
    let port = running.port;

    let graceful = http_post_shutdown(port, &token)
        && wait_child_exit(&mut child, Duration::from_secs(3));
    if !graceful {
        let _ = child_kill(child);
        log_err(app, &format!("[server] non-graceful kill after stop on port {port}"));
    } else {
        log_err(app, &format!("[server] stopped gracefully on port {port}"));
    }
    Ok(())
}

fn wait_child_exit(child: &mut Child, timeout: Duration) -> bool {
    let deadline = Instant::now() + timeout;
    loop {
        if let Some(_status) = child.try_wait().ok().flatten() {
            return true;
        }
        if Instant::now() >= deadline {
            return false;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn child_kill(mut child: Child) -> Result<(), String> {
    let exited = child.try_wait().ok().flatten().is_some();
    if !exited {
        child.kill().map_err(|e| e.to_string())?;
        child.wait().map_err(|e| e.to_string())?;
    }
    Ok(())
}

fn log_err(app: &AppHandle, line: &str) {
    use std::io::Write;
    if let Ok(dir) = app.path().app_data_dir() {
        if std::fs::create_dir_all(&dir).is_ok() {
            let log_path = dir.join("server.log");
            // Ротация: больше лимита — текущий файл в .1, новый пишется заново.
            if let Ok(meta) = std::fs::metadata(&log_path) {
                if meta.len() > SERVER_LOG_MAX_BYTES {
                    let _ = std::fs::remove_file(dir.join("server.log.1"));
                    let _ = std::fs::rename(&log_path, dir.join("server.log.1"));
                }
            }
            if let Ok(mut f) = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(&log_path)
            {
                let _ = writeln!(f, "{line}");
            }
        }
    }
}

/// Минимальное HTTP-подключение к 127.0.0.1 без внешних зависимостей.
fn tcp_connect(port: u16, timeout: Duration) -> Result<TcpStream, String> {
    let addr = std::net::SocketAddr::from(([127, 0, 0, 1], port));
    TcpStream::connect_timeout(&addr, timeout).map_err(|e| e.to_string())
}

/// GET /api/health — true, если сервер ответил 200.
fn http_get_health(port: u16, timeout: Duration) -> bool {
    let Ok(mut stream) = tcp_connect(port, timeout) else {
        return false;
    };
    let _ = stream.set_read_timeout(Some(timeout));
    let _ = stream.set_write_timeout(Some(timeout));
    let request = "GET /api/health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n";
    if stream.write_all(request.as_bytes()).is_err() {
        return false;
    }
    let mut buf = [0u8; 256];
    let mut total = 0usize;
    while total < buf.len() {
        match stream.read(&mut buf[total..]) {
            Ok(0) | Err(_) => break,
            Ok(n) => {
                total += n;
                if total >= buf.len() {
                    break;
                }
            }
        }
    }
    String::from_utf8_lossy(&buf[..total]).starts_with("HTTP/1.1 200")
}

/// POST /api/shutdown с токеном — запрашивает штатное завершение.
fn http_post_shutdown(port: u16, token: &str) -> bool {
    let timeout = Duration::from_secs(2);
    let Ok(mut stream) = tcp_connect(port, timeout) else {
        return false;
    };
    let _ = stream.set_read_timeout(Some(timeout));
    let _ = stream.set_write_timeout(Some(timeout));
    let body = "{}";
    let request = format!(
        "POST /api/shutdown HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer {token}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    if stream.write_all(request.as_bytes()).is_err() {
        return false;
    }
    // Сервер отвечает и сразу выходит; читать тело не обязательно — достаточно
    // дождаться закрытия соединения.
    let mut buf = [0u8; 128];
    let _ = stream.read(&mut buf);
    true
}

/// Снимает verbose-префикс `\\?\` который Windows std добавляет к путям
/// (значения resource_dir приходили в виде `\\?\C:\...`). Node-модульный
/// загрузчик не умеет грузить entry по extended-пути — процесс умирал молча.
#[cfg(windows)]
fn plain_path(p: &Path) -> PathBuf {
    let s = p.as_os_str().to_string_lossy().to_string();
    let plain = s
        .strip_prefix(r"\\?\UNC\")
        .map(|r| format!(r"\\{r}"))
        .or_else(|| s.strip_prefix(r"\\?\").map(|r| r.to_string()))
        .unwrap_or(s);
    PathBuf::from(plain)
}
#[cfg(not(windows))]
fn plain_path(p: &Path) -> PathBuf {
    p.to_path_buf()
}

#[tauri::command]
pub fn get_server_port(app: AppHandle, state: State<ServerState>) -> Result<u16, String> {
    ensure_server(&app, &state)
}

/// Порт + токен доступа. Фронтенд вызывает её один раз после старта и сразу
/// настраивает и базовый URL, и заголовок Authorization — без двух гонок.
#[tauri::command]
pub fn get_server_info(app: AppHandle, state: State<ServerState>) -> Result<ServerInfoDto, String> {
    ensure_server(&app, &state)?;
    let guard = state
        .inner
        .lock()
        .map_err(|_| "server state lock poisoned".to_string())?;
    guard
        .as_ref()
        .map(|running| ServerInfoDto {
            port: running.port,
            token: running.token.clone(),
        })
        .ok_or_else(|| "server not running".to_string())
}

#[tauri::command]
pub fn server_status(state: State<ServerState>) -> Result<ServerStatusDto, String> {
    let guard = state
        .inner
        .lock()
        .map_err(|_| "server state lock poisoned".to_string())?;
    Ok(match guard.as_ref() {
        Some(running) => ServerStatusDto {
            running: true,
            port: Some(running.port),
            pid: Some(running.child.id()),
        },
        None => ServerStatusDto {
            running: false,
            port: None,
            pid: None,
        },
    })
}

#[tauri::command]
pub fn stop_server_command(app: AppHandle, state: State<ServerState>) -> Result<(), String> {
    stop_server(&app, &state)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sidecar_node() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../server/sidecar/bin/node.exe")
    }

    fn node_script(ms: u64) -> Child {
        let node = sidecar_node();
        assert!(
            node.exists(),
            "построй sidecar (node server/build-sidecar.mjs): node binary not found at {}",
            node.display()
        );
        Command::new(&node)
            .arg("-e")
            .arg(format!("setTimeout(()=>{{}}, {ms});"))
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .expect("spawn sidecar node")
    }

    fn mock_http_server(respond: &'static [u8]) -> u16 {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let port = listener.local_addr().unwrap().port();
        std::thread::spawn(move || {
            if let Ok((mut stream, _)) = listener.accept() {
                let mut buf = [0u8; 1024];
                let _ = stream.read(&mut buf);
                let _ = stream.write_all(respond);
            }
        });
        port
    }

    #[test]
    fn token_is_long_hex_and_unique() {
        let a = generate_token();
        let b = generate_token();
        assert_eq!(a.len(), 48);
        assert!(a.chars().all(|c| c.is_ascii_hexdigit()));
        assert_ne!(a, b);
    }

    #[test]
    fn health_ok_when_server_returns_200() {
        let port = mock_http_server(
            b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok",
        );
        assert!(http_get_health(port, Duration::from_millis(2000)));
    }

    #[test]
    fn health_fails_when_nothing_listening() {
        // Порт освобождается сразу после drop — к моменту вызова слушателя
        // уже нет, connect получает ECONNREFUSED.
        let port = TcpListener::bind(("127.0.0.1", 0))
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        assert!(!http_get_health(port, Duration::from_millis(300)));
    }

    #[test]
    fn graceful_stop_sends_request_and_reads_response() {
        let port = mock_http_server(
            b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        );
        assert!(http_post_shutdown(port, "secret-token"));
    }

    #[test]
    fn wait_child_exit_returns_true_for_quick_child() {
        let mut child = node_script(100);
        assert!(wait_child_exit(&mut child, Duration::from_secs(5)));
    }

    #[test]
    fn wait_child_exit_times_out_for_lingering_child() {
        let mut child = node_script(5000);
        assert!(!wait_child_exit(&mut child, Duration::from_millis(200)));
        let _ = child.kill();
        let _ = child.wait();
    }
}