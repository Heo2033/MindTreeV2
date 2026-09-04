use tauri::AppHandle;

#[tauri::command]
pub fn load_settings(app: AppHandle) -> Result<String, String> {
    mindtree_native::load_settings(app)
}

#[tauri::command]
pub fn save_settings(app: AppHandle, settings: String) -> Result<(), String> {
    mindtree_native::save_settings(app, settings)
}

#[tauri::command]
pub fn store_secret(app: AppHandle, key: String, value: String) -> Result<(), String> {
    mindtree_native::store_secret(app, key, value)
}

#[tauri::command]
pub fn get_secret(app: AppHandle, key: String) -> Result<Option<String>, String> {
    mindtree_native::get_secret(app, key)
}

#[tauri::command]
pub fn delete_secret(app: AppHandle, key: String) -> Result<(), String> {
    mindtree_native::delete_secret(app, key)
}
