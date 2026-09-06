//! Общие Tauri-команды для desktop и studio: хранение настроек и секретов.
//! Секреты (API-ключи) хранятся в системном хранилище (keyring),
//! настройки — в JSON-файле в app_data_dir.

use std::fs;
use std::io::Write;
use std::path::Path;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};

use tauri::{AppHandle, Manager};

/// Монотонный счётчик для уникальных tmp-имён: таймстампы у двух потоков могут
/// совпасть (гранулярность системных часов), монотонный счётчик — нет.
static TMP_NONCE: AtomicU64 = AtomicU64::new(0);

/// Процесс-локальный мьютекс: сериализует read-check-write настроек в рамках
/// одного процесса (desktop и studio — однопроцессные приложения).
fn settings_lock() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
}

fn settings_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("app_data_dir: {e}"))?;
    fs::create_dir_all(&dir).map_err(|e| format!("create_dir_all {}: {e}", dir.display()))?;
    Ok(dir.join("settings.json"))
}

/// Пространство имён keyring для секретов — берём из app identifier,
/// чтобы desktop и studio не смешивали ключи.
fn service(app: &AppHandle) -> String {
    app.config().identifier.clone()
}

pub fn load_settings(app: AppHandle) -> Result<String, String> {
    let path = settings_path(&app)?;
    match fs::read_to_string(&path) {
        Ok(s) => Ok(s),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok("{}".to_string()),
        Err(e) => Err(e.to_string()),
    }
}

/// Сохранение настроек с оптимистичной блокировкой (CAS):
/// если `expected` задан и не совпадает с текущим содержимым файла,
/// возвращается ошибка конфликта — вызывающая сторона перечитывает и повторяет.
/// `expected = None` сохраняет обратную совместимость (безусловная запись).
pub fn save_settings(
    app: AppHandle,
    settings: String,
    expected: Option<String>,
) -> Result<(), String> {
    let path = settings_path(&app)?;

    validate_settings_object(&settings)?;

    let _guard = settings_lock()
        .lock()
        .map_err(|_| "settings lock poisoned".to_string())?;

    if let Some(exp) = &expected {
        let current = match fs::read_to_string(&path) {
            Ok(s) => s,
            // Первого сохранения ещё не было — эквивалент "{}".
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => "{}".to_string(),
            Err(e) => return Err(e.to_string()),
        };
        if current != *exp {
            return Err("settings changed concurrently, reload and retry".to_string());
        }
    }

    write_settings_atomic(&path, &settings)
}

/// Настройки должны быть валидным JSON-объектом, а не null/массивом/скаляром.
fn validate_settings_object(settings: &str) -> Result<(), String> {
    match serde_json::from_str::<serde_json::Value>(settings) {
        Ok(v) if v.is_object() => Ok(()),
        Ok(_) => Err("settings must be a JSON object".to_string()),
        Err(e) => Err(format!("invalid JSON: {e}")),
    }
}

/// Уборка битых tmp-файлов (json.tmp.* старше часа), оставшихся после сбоя
/// между write и rename. Живые записи не трогаем: rename занимает миллисекунды,
/// а конкурентные записи дополнительно замкованы мьютексом в `save_settings`.
pub fn cleanup_stale_tmp(app: &AppHandle) {
    let Ok(dir) = app.path().app_data_dir() else {
        return;
    };
    let Ok(entries) = fs::read_dir(&dir) else {
        return;
    };
    let Some(cutoff) =
        std::time::SystemTime::now().checked_sub(std::time::Duration::from_secs(3600))
    else {
        return;
    };
    for e in entries.flatten() {
        let name = e.file_name().to_string_lossy().into_owned();
        if name.starts_with("settings.json.tmp.") {
            let modified = e.metadata().and_then(|m| m.modified());
            if modified.map(|t| t < cutoff).unwrap_or(false) {
                let _ = fs::remove_file(e.path());
            }
        }
    }
}

/// Атомарная запись JSON-настроек: валидирует вход, пишет в уникальный
/// tmp-файл, fsync и затем rename (атомарная операция на всех целевых ФС).
fn write_settings_atomic(path: &Path, settings: &str) -> Result<(), String> {
    validate_settings_object(settings)?;

    // Уникальность: монотонный счётчик процесса + pid. Таймстампы не подходят:
    // два потока могут снять одинаковое значение системных часов и получить один
    // и тот же tmp-путь, что приведёт к гонке на файл.
    let nonce = TMP_NONCE.fetch_add(1, Ordering::Relaxed);
    let tmp = path.with_extension(format!("json.tmp.{}.{}", std::process::id(), nonce));

    // Пишем и синхронизируем один и тот же дескриптор (без второго open).
    // fsync гарантирует запись данных на диск до атомарного rename,
    // защищая от потери при системном сбое между write и rename.
    let write_and_sync = || -> Result<(), String> {
        let mut f = fs::File::create(&tmp).map_err(|e| format!("create tmp: {e}"))?;
        f.write_all(settings.as_bytes())
            .map_err(|e| format!("write tmp: {e}"))?;
        f.sync_all().map_err(|e| format!("fsync tmp: {e}"))
    };

    if let Err(e) = write_and_sync() {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }

    fs::rename(&tmp, path).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        format!("rename: {e}")
    })
}

pub fn store_secret(app: AppHandle, key: String, value: String) -> Result<(), String> {
    let entry = keyring::Entry::new(&service(&app), &key).map_err(|e| e.to_string())?;
    entry
        .set_secret(value.as_bytes())
        .map_err(|e| e.to_string())
}

pub fn get_secret(app: AppHandle, key: String) -> Result<Option<String>, String> {
    let entry = keyring::Entry::new(&service(&app), &key).map_err(|e| e.to_string())?;
    match entry.get_secret() {
        // Строгое преобразование: lossy-подмена байт молча портила бы секрет.
        Ok(bytes) => {
            let s = String::from_utf8(bytes).map_err(|e| format!("secret is not UTF-8: {e}"))?;
            Ok(Some(s))
        }
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

pub fn delete_secret(app: AppHandle, key: String) -> Result<(), String> {
    let entry = keyring::Entry::new(&service(&app), &key).map_err(|e| e.to_string())?;
    match entry.delete_credential() {
        Ok(()) => Ok(()),
        Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(e.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn temp_path() -> (tempfile::TempDir, std::path::PathBuf) {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("settings.json");
        (dir, path)
    }

    #[test]
    fn saves_and_loads_settings() {
        let (_dir, path) = temp_path();

        write_settings_atomic(&path, r#"{"provider":"openai","model":"gpt-4"}"#)
            .expect("should save valid JSON");

        let raw = fs::read_to_string(&path).expect("file should exist");
        let parsed: serde_json::Value = serde_json::from_str(&raw).expect("stored JSON is valid");
        assert_eq!(parsed["provider"], "openai");
        assert_eq!(parsed["model"], "gpt-4");
    }

    #[test]
    fn rejects_invalid_json() {
        let (_dir, path) = temp_path();

        let err = write_settings_atomic(&path, "{not valid json}").unwrap_err();
        assert!(err.contains("invalid JSON"), "unexpected error: {err}");
        assert!(
            !path.exists(),
            "target must not be created on invalid input"
        );
    }

    #[test]
    fn rejects_non_object_json() {
        let (_dir, path) = temp_path();

        for bad in [r#"[1,2,3]"#, r#"null"#, r#""str""#, r#"42"#] {
            let err = write_settings_atomic(&path, bad).unwrap_err();
            assert!(
                err.contains("must be a JSON object"),
                "unexpected error for {bad}: {err}"
            );
            assert!(!path.exists(), "target must not be created for {bad}");
        }
    }

    #[test]
    fn leaves_no_tmp_files_behind() {
        let (_dir, path) = temp_path();

        write_settings_atomic(&path, r#"{"a":1}"#).expect("save ok");

        // В tempdir не должно остаться tmp-файлов (json.tmp.*)
        let leftovers: Vec<_> = fs::read_dir(_dir.path())
            .expect("read dir")
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().contains(".tmp"))
            .collect();
        assert!(leftovers.is_empty(), "leftover tmp files: {leftovers:?}");
    }

    #[test]
    fn overwrites_existing_settings() {
        let (_dir, path) = temp_path();

        write_settings_atomic(&path, r#"{"v":1}"#).expect("first save");
        write_settings_atomic(&path, r#"{"v":2,"extra":true}"#).expect("second save");

        let raw = fs::read_to_string(&path).expect("file");
        let parsed: serde_json::Value = serde_json::from_str(&raw).unwrap();
        assert_eq!(parsed["v"], 2);
        assert_eq!(parsed["extra"], true);
    }

    #[test]
    fn concurrent_writes_produce_consistent_file() {
        let (_dir, path) = temp_path();

        let mut handles = Vec::new();
        for i in 0..8 {
            let p = path.clone();
            handles.push(std::thread::spawn(move || {
                let payload = format!(r#"{{"n":{i}}}"#);
                write_settings_atomic(&p, &payload).expect("concurrent save");
            }));
        }
        for h in handles {
            h.join().expect("thread panicked");
        }

        // Файл всегда целый и валидный — одно из состояний победило.
        let raw = fs::read_to_string(&path).expect("file");
        let parsed: serde_json::Value = serde_json::from_str(&raw).expect("always valid JSON");
        assert!(parsed.is_object());
    }
}
