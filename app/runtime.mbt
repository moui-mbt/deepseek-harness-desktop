///|
/// Platform-neutral composition for the DSH WebView program. Native roots
/// wrap this program in `@runtime.new_program_with_dimensions` before adding
/// their renderer and backend.
pub fn runtime(
  capabilities~ : @webview_host.HostWebViewCapabilities,
  controller~ : @webview_host.WebViewController,
  chat_controller? : @webview_host.WebViewController? = None,
  environment? : @services.AppEnvironment = @services.AppEnvironment::new(),
  dsh_service? : DshService = DshService::unavailable(),
  url? : String = default_url,
  on_navigation_finished? : (String) -> Unit = _ => (),
  no_drag_regions? : (Double) -> Array[@webview_host.WebViewNoDragRegion] = _ => {
    []
  },
) -> @moui.Program[Model, Msg] {
  program(
    capability=if capabilities.available {
      WebViewCapability::available(description=capabilities.description)
    } else {
      WebViewCapability::unavailable(description=capabilities.description)
    },
    controller=Some(controller),
    chat_controller~,
    environment~,
    dsh_service~,
    url~,
    on_navigation_finished~,
    no_drag_regions~,
  )
}

///|
/// Composition roots provide any platform-specific HostPatch bundles. Origins
/// remain exact native policy values; the page cannot widen them through a
/// bridge envelope.
pub fn create_controller(
  host : @webview_host.WebViewHost,
  host_patches? : Array[@webview_host.HostPatchBundle] = [],
) -> @webview_host.WebViewController {
  create_controller_with_id(host, "dsh-desktop-surface", host_patches)
}

///|
pub fn create_chat_controller(
  host : @webview_host.WebViewHost,
  host_patches? : Array[@webview_host.HostPatchBundle] = [],
) -> @webview_host.WebViewController {
  create_controller_with_id(host, "dsh-desktop-chat-surface", host_patches)
}

///|
fn create_controller_with_id(
  host : @webview_host.WebViewHost,
  id : String,
  host_patches : Array[@webview_host.HostPatchBundle],
) -> @webview_host.WebViewController {
  let origins = [
    @webview_host.WebViewOrigin::parse(default_url).unwrap(),
    @webview_host.WebViewOrigin::parse(default_chat_url).unwrap(),
  ]
  let security = @webview_host.WebViewSecurityPolicy::new(
    allowed_origins=origins.copy(),
    allowed_channels=[
      @webview_host.WebViewChannelPolicy::new(
        name="dsh.event",
        direction=@webview_host.WebViewChannelDirection::Bidirectional,
      ),
      @webview_host.WebViewChannelPolicy::new(
        name="dsh.request",
        direction=@webview_host.WebViewChannelDirection::Bidirectional,
      ),
    ],
  )
  host
  .create_controller(
    id~,
    config=@webview_host.WebViewControllerConfig::new(
      security~,
      host_patches~,
      capabilities=if host_patches.length() > 0 {
        ["bridge-v1", "host-patch-v1"]
      } else {
        ["bridge-v1"]
      },
    ),
  )
  .unwrap()
}
