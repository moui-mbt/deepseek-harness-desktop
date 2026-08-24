///|
pub fn program(
  capability~ : WebViewCapability,
  controller? : @webview_host.WebViewController? = None,
  chat_controller? : @webview_host.WebViewController? = None,
  environment? : @services.AppEnvironment = @services.AppEnvironment::new(),
  dsh_service? : DshService = DshService::mock(initial_running=true),
  url? : String = default_url,
  on_navigation_finished? : (String) -> Unit = _ => (),
  no_drag_regions? : (Double) -> Array[@webview_host.WebViewNoDragRegion] = _ => {
    []
  },
) -> @moui.Program[Model, Msg] {
  let controller = match controller {
    Some(value) => Some(value)
    None if capability.available => Some(test_or_preview_controller())
    None => None
  }
  let services = environment.services()
  let timer_source = environment.timer()
  @moui.Program::new_with_environment(
    init=() => {
      let initial = Model::new(capability~, url~)
      let settings = request_settings_load(services)
      (initial, settings)
    },
    update=(model, msg) => {
      let (next, effect) = update_with_services(model, msg, services)
      let site_navigation = match (controller, chat_controller, msg) {
        (Some(_), Some(_), SwitchSite) => @moui.Effect::none()
        (Some(controller), None, SwitchSite) =>
          navigate_webview(controller, next.url)
        _ => @moui.Effect::none()
      }
      let preload_navigation = if !model.settings_ready && next.settings_ready {
        let chat = match chat_controller {
          Some(controller) => navigate_webview(controller, next.chat_url)
          None => @moui.Effect::none()
        }
        let harness = match controller {
          Some(controller) if next.dsh_web_status == DshWebStatus::Running =>
            navigate_webview(controller, next.harness_url)
          _ => @moui.Effect::none()
        }
        @moui.Effect::batch([harness, chat])
      } else {
        @moui.Effect::none()
      }
      let lifecycle_navigation = match (controller, msg) {
        (
          Some(controller),
          DshCheckResult(@services.ServiceTaskResult::Success(true)),
        ) if model.dsh_web_status == DshWebStatus::Starting &&
          next.dsh_web_status == DshWebStatus::Running =>
          navigate_webview(controller, next.harness_url)
        (
          Some(controller),
          DshStopResult(@services.ServiceTaskResult::Success(_)),
        ) =>
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
      let settings_navigation = match msg {
        HarnessSettingsSaved(value, @services.ServiceTaskResult::Success(_)) if value !=
          model.harness_url =>
          match controller {
            Some(controller) => navigate_webview(controller, value)
            None => @moui.Effect::none()
          }
        ChatSettingsSaved(value, @services.ServiceTaskResult::Success(_)) if value !=
          model.chat_url =>
          match (controller, chat_controller, model.active_site) {
            (_, Some(controller), _) => navigate_webview(controller, value)
            (Some(controller), None, Chat) =>
              navigate_webview(controller, value)
            _ => @moui.Effect::none()
          }
        SettingsSaved(value, @services.ServiceTaskResult::Success(_)) if value !=
          model.harness_url =>
          match controller {
            Some(controller) => navigate_webview(controller, value)
            None => @moui.Effect::none()
          }
        _ => @moui.Effect::none()
      }
      let dsh_effect = match msg {
        SettingsLoaded(_) if next.harness_settings_ready =>
          dsh_service
          .check(harness_url=next.harness_url)
          .effect(map=result => DshCheckResult(result))
        StartDshWeb if model.dsh_web_status == DshWebStatus::Stopped =>
          dsh_service
          .start(harness_url=next.harness_url)
          .effect(map=result => DshStartResult(result))
        StopDshWeb if model.dsh_web_status == DshWebStatus::Running ||
          model.dsh_web_status == DshWebStatus::Starting =>
          dsh_service
          .stop(harness_url=model.harness_url)
          .effect(map=result => DshStopResult(result))
        DshStartResult(@services.ServiceTaskResult::Success(_)) if model.dsh_web_status ==
          DshWebStatus::Starting =>
          dsh_service
          .check(harness_url=model.harness_url)
          .effect(map=result => DshCheckResult(result))
        DshProbeTick if model.dsh_web_status == DshWebStatus::Starting &&
          model.dsh_start_probes_remaining > 0 =>
          dsh_service
          .check(harness_url=model.harness_url)
          .effect(map=result => DshCheckResult(result))
        DshCheckResult(@services.ServiceTaskResult::Success(false)) if model.dsh_web_status ==
          DshWebStatus::Starting &&
          model.dsh_start_probes_remaining == 1 =>
          dsh_service
          .stop(harness_url=model.harness_url)
          .effect(map=result => DshCleanupResult(result))
        _ => @moui.Effect::none()
      }
      match msg {
        WebViewEvent(@webview_host.WebViewEvent::NavigationFinished(navigation)) =>
          on_navigation_finished(navigation.url)
        _ => ()
      }
      (
        next,
        @moui.Effect::batch([
          effect, site_navigation, preload_navigation, lifecycle_navigation, settings_navigation,
          dsh_effect,
        ]),
      )
    },
    view=(model, view_environment) => {
      view_with_environment(
        model, view_environment, controller, chat_controller, no_drag_regions,
      )
    },
    subscriptions=model => {
      match timer_source {
        Some(source) if model.dsh_web_status == DshWebStatus::Starting &&
          model.dsh_start_probes_remaining > 0 =>
          source.subscription(
            interval_ms=dsh_start_probe_interval_ms,
            key="dsh:start-readiness",
            label="DSH start readiness probe",
            map=_ => DshProbeTick,
          )
        _ => @moui.Subscription::none()
      }
    },
  ).with_commands(commands=model => program_commands(model))
}

///|
fn navigate_webview(
  controller : @webview_host.WebViewController,
  url : String,
) -> @moui.Effect[Msg] {
  controller
  .navigate(url)
  .effect(map=result => {
    match result {
      @webview_host.WebViewTaskResult::Success(_) =>
        WebViewEvent(@webview_host.WebViewEvent::Ready([]))
      _ => WebViewEvent(@webview_host.WebViewEvent::Disposed)
    }
  })
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
