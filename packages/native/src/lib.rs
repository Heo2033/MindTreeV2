//! Общие Tauri-команды для desktop и studio: хранение настроек и секретов.
//! Секреты (API-ключи) хранятся в системном хранилище (keyring),
//! настройки — в JSON-файле в app_data_dir.

use std::fs;
use std::path::PathBuf;
use tauri::{AppHandle, Manager};

fn settings_path(app: &AppHandle) -> PathBuf {
    let dir = app
        .path()
        .app_data_dir()
        .expect("failed to resolve app data dir");
    fs::create_dir_all(&dir).ok();
    dir.join("settings.json")
}

/// Пространство имён keyring для секретов — берём из app identifier,
/// чтобы desktop и studio не смешивали ключи.
fn service(app: &AppHandle) -> String {
    app.config().identifier.clone()
}

pub fn load_settings(app: AppHandle) -> Result<String, String> {
    let path = settings_path(&app);
    if path.exists() {
        fs::read_to_string(&path).map_err(|e| e.to_string())
    } else {
        Ok("{}".to_string())
    }
}

pub fn save_settings(app: AppHandle, settings: String) -> Result<(), String> {
    let path = settings_path(&app);
    fs::write(&path, settings).map_err(|e| e.to_string())
}

pub fn store_secret(app: AppHandle, key: String, value: String) -> Result<(), String> {
    let entry = keyring::Entry::new(&service(&app), &key).map_err(|e| e.to_string())?;
    entry.set_secret(value.as_bytes()).map_err(|e| e.to_string())
}

pub fn get_secret(app: AppHandle, key: String) -> Result<Option<String>, String> {
    let entry = keyring::Entry::new(&service(&app), &key).map_err(|e| e.to_string())?;
    match entry.get_secret() {
        Ok(bytes) => Ok(Some(String::from_utf8(bytes).map_err(|e| e.to_string())?)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

pub fn delete_secret(app: AppHandle, key: String) -> Result<(), String> {
    let entry = keyring::Entry::new(&service(&app), &key).map_err(|e| e.to_string())?;
    entry.delete_credential().map_err(|e| e.to_string())
}
