//! Общие Tauri-команды для desktop и studio: хранение настроек и секретов.
//! Секреты (API-ключи) хранятся в системном хранилище (keyring),
//! настройки — в JSON-файле в app_data_dir.

use std::fs;
use std::path::PathBuf;
use tauri::{AppHandle, Manager};

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

pub fn save_settings(app: AppHandle, settings: String) -> Result<(), String> {
    let path = settings_path(&app)?;
    write_settings_atomic(&path, &settings)
}

/// Атомарная запись JSON-настроек: валидирует вход, пишет в уникальный
/// tmp-файл, fsync и затем rename (атомарная операция на всех целевых ФС).
fn write_settings_atomic(path: &std::path::Path, settings: &str) -> Result<(), String> {
    serde_json::from_str::<serde_json::Value>(settings)
        .map_err(|e| format!("invalid JSON: {e}"))?;

    // Уникальный tmp-файл на вызов: исключает lost-update между
    // конкурентными записями, которые пишут в один и тот же путь.
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_nanos();
    let tmp = path.with_extension(format!("json.tmp.{nonce}"));

    fs::write(&tmp, settings).map_err(|e| format!("write tmp: {e}"))?;

    // fsync гарантирует запись данных на диск до атомарного rename,
    // защищая от потери при системном сбое между write и rename.
    // На Windows sync_all требует descriptor с правом записи.
    if let Err(e) = fs::OpenOptions::new().write(true).open(&tmp).and_then(|f| f.sync_all()) {
        let _ = fs::remove_file(&tmp);
        return Err(format!("fsync tmp: {e}"));
    }

    fs::rename(&tmp, path).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        format!("rename: {e}")
    })
}

pub fn store_secret(app: AppHandle, key: String, value: String) -> Result<(), String> {
    let entry = keyring::Entry::new(&service(&app), &key).map_err(|e| e.to_string())?;
    entry.set_secret(value.as_bytes()).map_err(|e| e.to_string())
}

pub fn get_secret(app: AppHandle, key: String) -> Result<Option<String>, String> {
    let entry = keyring::Entry::new(&service(&app), &key).map_err(|e| e.to_string())?;
    match entry.get_secret() {
        Ok(bytes) => Ok(Some(String::from_utf8_lossy(&bytes).into_owned())),
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
        assert!(!path.exists(), "target must not be created on invalid input");
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
