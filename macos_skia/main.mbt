///|
async fn main {
  @async.with_task_group(group => {
    let host = @webview_host.WebViewHost::new()
    let shell_patch = dsh_shell_patch()
    let controller = @app.create_controller(host, host_patches=[shell_patch])
    let chat_controller = @app.create_chat_controller(host)
    let plugin = @macos_webview.create_macos_webview_plugin(host)
    let capabilities = @macos_webview.macos_webview_capabilities()
    let environment = @macos_backend.app_environment()
    let dsh_service = @dsh_async.service(group)
    let program = @app.runtime(
      capabilities~,
      controller~,
      chat_controller=Some(chat_controller),
      environment~,
      dsh_service~,
      no_drag_regions=dsh_top_no_drag_regions,
    )
    let runtime = @runtime.new_program_with_dimensions(
      program~,
      width=1280.0,
      height=820.0,
    )
    let menus = @app.application_menus()
    @runtime.run_app("DSH Desktop", runtime)
    .render_all(
      @render_skia.from_env(platform=@render_skia.NativeGpuPlatform::MacOS),
    )
    .backend(
      @macos_backend.entry(
        options=@macos_backend.MacosHostAppOptions::new(
          transparent_titlebar=true,
          platform_view_plugins=[plugin],
          on_ready=Some(
            @macos_backend.application_menu_on_ready(menus, runtime),
          ),
        ),
      ),
    )
    .run_async_pump()
  })
}
