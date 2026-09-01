use tauri::AppHandle;

#[tauri::command]
fn load_settings(app: AppHandle) -> Result<String, String> {
    mindtree_native::load_settings(app)
}

#[tauri::command]
fn save_settings(app: AppHandle, settings: String) -> Result<(), String> {
    mindtree_native::save_settings(app, settings)
}

#[tauri::command]
fn store_secret(app: AppHandle, key: String, value: String) -> Result<(), String> {
    mindtree_native::store_secret(app, key, value)
}

#[tauri::command]
fn get_secret(app: AppHandle, key: String) -> Result<Option<String>, String> {
    mindtree_native::get_secret(app, key)
}

#[tauri::command]
fn delete_secret(app: AppHandle, key: String) -> Result<(), String> {
    mindtree_native::delete_secret(app, key)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_http::init())
        .invoke_handler(tauri::generate_handler![
            load_settings,
            save_settings,
            store_secret,
            get_secret,
            delete_secret,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
