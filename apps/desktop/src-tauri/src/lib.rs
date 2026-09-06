mod server_manager;

use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_single_instance::init(|_app, _args, _cwd| {
            // Второй экземпляр не запускает сервер повторно; окно первого уже
            // открыто. Можно добавить фокус/подъём окна, если потребуется.
        }))
        .manage(server_manager::ServerState::default())
        .invoke_handler(tauri::generate_handler![
            mindtree_tauri_common::commands::load_settings,
            mindtree_tauri_common::commands::save_settings,
            mindtree_tauri_common::commands::store_secret,
            mindtree_tauri_common::commands::get_secret,
            mindtree_tauri_common::commands::delete_secret,
            server_manager::get_server_port,
            server_manager::server_status,
            server_manager::stop_server_command,
        ])
        .setup(|app| {
            mindtree_native::cleanup_stale_tmp(app.handle());
            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                let state = handle.state::<server_manager::ServerState>();
                match server_manager::ensure_server(&handle, &state) {
                    Ok(port) => log_server_ready(port),
                    Err(e) => log_server_error(&e),
                }
            });
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application");

    app.run(|app_handle, event| {
        if let tauri::RunEvent::Exit = event {
            let state = app_handle.state::<server_manager::ServerState>();
            let _ = server_manager::stop_server(&state);
        }
    });
}

fn log_server_ready(port: u16) {
    println!("[server] embedded server listening on http://127.0.0.1:{port}");
}

fn log_server_error(err: &str) {
    eprintln!("[server] failed to start embedded server: {err}");
}
