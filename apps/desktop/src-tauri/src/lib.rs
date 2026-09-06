#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_http::init())
        .invoke_handler(tauri::generate_handler![
            mindtree_tauri_common::commands::load_settings,
            mindtree_tauri_common::commands::save_settings,
            mindtree_tauri_common::commands::store_secret,
            mindtree_tauri_common::commands::get_secret,
            mindtree_tauri_common::commands::delete_secret,
        ])
        .setup(|app| {
            mindtree_native::cleanup_stale_tmp(app.handle());
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
