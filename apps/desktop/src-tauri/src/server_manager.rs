//! Управление жизненным циклом встроенного Node-сервера (sidecar).
//!
//! Один процесс приложения = один локальный сервер. Rust выбирает свободный
//! порт, запускает бандл `server/sidecar` через bundled `node`, следит за
//! состоянием и корректно гасит процесс при выходе.

use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::Mutex;

use tauri::{AppHandle, Manager, State};

pub struct ServerState(Mutex<Option<RunningServer>>);

pub struct RunningServer {
    pub port: u16,
    child: Child,
}

#[derive(serde::Serialize)]
pub struct ServerStatusDto {
    pub running: bool,
    pub port: Option<u16>,
    pub pid: Option<u32>,
}

impl Default for ServerState {
    fn default() -> Self {
        ServerState(Mutex::new(None))
    }
}

/// Берём произвольный свободный порт на loopback. Слушатель тут же
/// закрывается — микро-гонка на порт при локальном запуске приемлема.
fn free_port() -> Result<u16, String> {
    let listener = TcpListener::bind(("127.0.0.1", 0)).map_err(|e| e.to_string())?;
    Ok(listener.local_addr().map_err(|e| e.to_string())?.port())
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
pub fn ensure_server(app: &AppHandle, state: &State<ServerState>) -> Result<u16, String> {
    let mut guard = state
        .0
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
        .spawn()
        .map_err(|e| format!("spawn node ({}) failed: {e}", node.display()))?;
    log_err(
        app,
        &format!("[server] spawned pid={} port={port}", child.id()),
    );

    *guard = Some(RunningServer { port, child });
    Ok(port)
}

fn log_err(app: &AppHandle, line: &str) {
    use std::io::Write;
    if let Ok(dir) = app.path().app_data_dir() {
        if std::fs::create_dir_all(&dir).is_ok() {
            if let Ok(mut f) = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(dir.join("server.log"))
            {
                let _ = writeln!(f, "{line}");
            }
        }
    }
}

/// Гасит встроенный сервер (если он ещё жив).
pub fn stop_server(state: &State<ServerState>) -> Result<(), String> {
    let mut guard = state
        .0
        .lock()
        .map_err(|_| "server state lock poisoned".to_string())?;
    if let Some(running) = guard.take() {
        kill_child(running.child);
    }
    Ok(())
}

fn kill_child(mut child: Child) {
    let exited = child.try_wait().ok().flatten().is_some();
    if !exited {
        let _ = child.kill();
        let _ = child.wait();
    }
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

#[tauri::command]
pub fn server_status(state: State<ServerState>) -> Result<ServerStatusDto, String> {
    let guard = state
        .0
        .lock()
        .map_err(|_| "server state lock poisoned".to_string())?;
    Ok(match guard.as_ref() {
        Some(running) => ServerStatusDto {
            running: true,
            port: Some(running.port),
            pid: running.child.id().into(),
        },
        None => ServerStatusDto {
            running: false,
            port: None,
            pid: None,
        },
    })
}

#[tauri::command]
pub fn stop_server_command(state: State<ServerState>) -> Result<(), String> {
    stop_server(&state)
}
