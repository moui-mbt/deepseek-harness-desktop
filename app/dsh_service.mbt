///|
/// DSH lifecycle service. This keeps the example-local DSH Web management out
/// of `moui/core` and `moui/services`.
///
/// `check` probes whether the Harness TCP endpoint is reachable. `start`
/// starts a `dsh` process and `stop` terminates it. The native-only
/// `app/dsh_async` package provides the real process implementation; this
/// package keeps the interface and the in-memory preview/test implementation
/// platform-neutral.
pub struct DshService {
  check_fn : (String) -> @services.ServiceTask[Bool]
  start_fn : (String) -> @services.ServiceTask[Unit]
  stop_fn : (String) -> @services.ServiceTask[Unit]
}

///|
pub fn DshService::new(
  check? : (String) -> @services.ServiceTask[Bool] = _ => {
    @services.ServiceTask::fail(
      key="dsh:check",
      error=@services.ServiceError::new(
        code="unavailable",
        message="dsh check unavailable",
      ),
    )
  },
  start? : (String) -> @services.ServiceTask[Unit] = _ => {
    @services.ServiceTask::fail(
      key="dsh:start",
      error=@services.ServiceError::new(
        code="unavailable",
        message="dsh start unavailable",
      ),
    )
  },
  stop? : (String) -> @services.ServiceTask[Unit] = _ => {
    @services.ServiceTask::fail(
      key="dsh:stop",
      error=@services.ServiceError::new(
        code="unavailable",
        message="dsh stop unavailable",
      ),
    )
  },
) -> DshService {
  { check_fn: check, start_fn: start, stop_fn: stop }
}

///|
pub fn DshService::check(
  self : DshService,
  harness_url? : String = default_url,
) -> @services.ServiceTask[Bool] {
  (self.check_fn)(harness_url)
}

///|
pub fn DshService::start(
  self : DshService,
  harness_url? : String = default_url,
) -> @services.ServiceTask[Unit] {
  (self.start_fn)(harness_url)
}

///|
pub fn DshService::stop(
  self : DshService,
  harness_url? : String = default_url,
) -> @services.ServiceTask[Unit] {
  (self.stop_fn)(harness_url)
}

///|
pub fn DshService::unavailable() -> DshService {
  DshService::new()
}

///|
/// In-memory mock for tests and WASM preview. `running` is shared via `Ref`
/// so `check` reflects the result of `start`/`stop`.
pub fn DshService::mock(initial_running? : Bool = false) -> DshService {
  let running = Ref(initial_running)
  DshService::new(
    check=_ => {
      @services.ServiceTask::succeed(key="dsh:check:mock", value=running.val)
    },
    start=_ => {
      running.val = true
      @services.ServiceTask::succeed(key="dsh:start:mock", value=())
    },
    stop=_ => {
      running.val = false
      @services.ServiceTask::succeed(key="dsh:stop:mock", value=())
    },
  )
}
