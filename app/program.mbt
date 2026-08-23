///|
pub fn program(
  capability~ : WebViewCapability,
  controller? : @webview_host.WebViewController? = None,
  environment? : @services.AppEnvironment = @services.AppEnvironment::new(),
  dsh_service? : DshService = DshService::mock(initial_running=true),
  url? : String = default_url,
  on_navigation_finished? : (String) -> Unit = _ => (),
) -> @moui.Program[Model, Msg] {
  let controller = match controller {
    Some(value) => Some(value)
    None if capability.available => Some(test_or_preview_controller())
    None => None
  }
  let services = environment.services()
  @moui.Program::new_with_environment(
    init=() => {
      let initial = Model::new(capability~, url~)
      let settings = request_settings_load(services)
      let dsh_check = dsh_service
        .check()
        .effect(map=result => DshCheckResult(result))
      let navigation = match controller {
        Some(controller) =>
          controller
          .navigate(initial.url)
          .effect(map=result => {
            match result {
              @webview_host.WebViewTaskResult::Success(_) =>
                WebViewEvent(@webview_host.WebViewEvent::Ready([]))
              _ => WebViewEvent(@webview_host.WebViewEvent::Disposed)
            }
          })
        None => @moui.Effect::none()
      }
      (initial, @moui.Effect::batch([settings, dsh_check, navigation]))
    },
    update=(model, msg) => {
      let (next, effect) = update_with_services(model, msg, services)
      let navigation = match (controller, msg) {
        (Some(controller), SwitchSite) =>
          controller
          .navigate(next.url)
          .effect(map=result => {
            match result {
              @webview_host.WebViewTaskResult::Success(_) =>
                WebViewEvent(@webview_host.WebViewEvent::Ready([]))
              _ => WebViewEvent(@webview_host.WebViewEvent::Disposed)
            }
          })
        (Some(controller), StartDshWeb) =>
          if model.url == next.url {
            controller
            .reload()
            .effect(map=result => {
              match result {
                @webview_host.WebViewTaskResult::Success(_) =>
                  WebViewEvent(@webview_host.WebViewEvent::Ready([]))
                _ => WebViewEvent(@webview_host.WebViewEvent::Disposed)
              }
            })
          } else {
            controller
            .navigate(next.url)
            .effect(map=result => {
              match result {
                @webview_host.WebViewTaskResult::Success(_) =>
                  WebViewEvent(@webview_host.WebViewEvent::Ready([]))
                _ => WebViewEvent(@webview_host.WebViewEvent::Disposed)
              }
            })
          }
        (Some(controller), StopDshWeb) =>
          controller
          .stop()
          .effect(map=result => {
            match result {
              @webview_host.WebViewTaskResult::Success(_) =>
                WebViewEvent(@webview_host.WebViewEvent::Ready([]))
              _ => WebViewEvent(@webview_host.WebViewEvent::Disposed)
            }
          })
        _ => @moui.Effect::none()
      }
      let dsh_effect = match msg {
        StartDshWeb =>
          dsh_service.start().effect(map=result => DshStartResult(result))
        StopDshWeb =>
          dsh_service.stop().effect(map=result => DshStopResult(result))
        _ => @moui.Effect::none()
      }
      let menu_effect = if model.dsh_web_status != next.dsh_web_status {
        services
        .menus()
        .install_application(application_menus(model=Some(next)))
        .effect(map=_ => SettingsBackdropPressed)
      } else {
        @moui.Effect::none()
      }
      match msg {
        WebViewEvent(@webview_host.WebViewEvent::NavigationFinished(navigation)) =>
          on_navigation_finished(navigation.url)
        _ => ()
      }
      (next, @moui.Effect::batch([effect, navigation, dsh_effect, menu_effect]))
    },
    view=(model, view_environment) => {
      view_with_environment(model, view_environment, controller)
    },
  ).with_commands(commands=model => program_commands(model))
}

///|
/// Preview/test fallback. Native composition roots inject the policy-bound
/// controller from `runtime.mbt`; tests still get a controller when available.
fn test_or_preview_controller() -> @webview_host.WebViewController {
  let host = @webview_host.WebViewHost::new()
  let security = @webview_host.WebViewSecurityPolicy::new(allowed_origins=[
    @webview_host.WebViewOrigin::parse(default_url).unwrap(),
    @webview_host.WebViewOrigin::parse(default_chat_url).unwrap(),
  ])
  host
  .create_controller(
    id="dsh-desktop-surface",
    config=@webview_host.WebViewControllerConfig::new(security~),
  )
  .unwrap()
}
