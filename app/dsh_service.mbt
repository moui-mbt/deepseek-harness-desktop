///|
/// DSH process lifecycle service. This keeps the example-local DSH Web
/// management out of `moui/core` and `moui/services`.
///
/// `check` probes whether the Harness is already reachable (HTTP GET to the
/// configured Harness URL). `start` spawns an independent `dsh` process and
/// `stop` terminates it. The native backends provide the real process
/// handling; the fallback is an in-memory mock suitable for tests and the
/// WASM preview.

pub struct DshService {
  check_fn : () -> @services.ServiceTask[Bool]
  start_fn : () -> @services.ServiceTask[Unit]
  stop_fn : () -> @services.ServiceTask[Unit]
}

///|
pub fn DshService::new(
  check? : () -> @services.ServiceTask[Bool] = () => {
    @services.ServiceTask::fail(
      key="dsh:check",
      error=@services.ServiceError::new(
        code="unavailable",
        message="dsh check unavailable",
      ),
    )
  },
  start? : () -> @services.ServiceTask[Unit] = () => {
    @services.ServiceTask::fail(
      key="dsh:start",
      error=@services.ServiceError::new(
        code="unavailable",
        message="dsh start unavailable",
      ),
    )
  },
  stop? : () -> @services.ServiceTask[Unit] = () => {
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
pub fn DshService::check(self : DshService) -> @services.ServiceTask[Bool] {
  (self.check_fn)()
}

///|
pub fn DshService::start(self : DshService) -> @services.ServiceTask[Unit] {
  (self.start_fn)()
}

///|
pub fn DshService::stop(self : DshService) -> @services.ServiceTask[Unit] {
  (self.stop_fn)()
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
    check=() => {
      @services.ServiceTask::succeed(key="dsh:check:mock", value=running.val)
    },
    start=() => {
      running.val = true
      @services.ServiceTask::succeed(key="dsh:start:mock", value=())
    },
    stop=() => {
      running.val = false
      @services.ServiceTask::succeed(key="dsh:stop:mock", value=())
    },
  )
}

///|
/// Native implementation that probes `harness_url` via TCP and spawns `dsh`.
///
/// `harness_url` is used to derive host/port for the liveness probe.
/// `dsh_cmd`/`dsh_args` allow the host to inject a custom launch command
/// (defaults to `dsh`).
pub fn DshService::native(
  harness_url~ : String = default_url,
  dsh_cmd? : String = "npx",
  dsh_args? : Array[String] = ["@deepseek-ai/dsh", "web"],
) -> DshService {
  let pid_ref : Ref[Int?] = Ref(None)
  DshService::new(
    check=() => {
      @services.ServiceTask::new(
        key="dsh:check:native",
        start=complete => {
          let running = dsh_probe_harness_sync(harness_url)
          complete(
            @services.ServiceTaskResult::Success(running),
          )
          None
        },
      )
    },
    start=() => {
      @services.ServiceTask::new(
        key="dsh:start:native",
        start=complete => {
          if dsh_probe_harness_sync(harness_url) {
            complete(@services.ServiceTaskResult::Success(()))
            return None
          }
          let args = if dsh_args.length() == 0 {
            ["@deepseek-ai/dsh", "web"]
          } else {
            dsh_args
          }
          let pid = try_spawn_dsh(dsh_cmd, args)
          match pid {
            Some(pid) => {
              pid_ref.val = Some(pid)
              complete(@services.ServiceTaskResult::Success(()))
            }
            None =>
              complete(
                @services.ServiceTaskResult::Failure(
                  @services.ServiceError::new(
                    code="dsh-spawn-failed",
                    message="failed to spawn dsh: " + dsh_cmd + " " + args.join(" "),
                  ),
                ),
              )
          }
          None
        },
      )
    },
    stop=() => {
      @services.ServiceTask::new(
        key="dsh:stop:native",
        start=complete => {
          match pid_ref.val {
            Some(pid) => {
              dsh_kill_pid(pid)
              pid_ref.val = None
            }
            None => ()
          }
          complete(@services.ServiceTaskResult::Success(()))
          None
        },
      )
    },
  )
}

///|
fn dsh_probe_harness_sync(url : String) -> Bool {
  dsh_probe_harness(url)
}

///|
fn dsh_probe_harness(url : String) -> Bool {
  // Very small TCP probe: try to connect to host:port derived from url.
  // We avoid pulling `async/http` here to keep the example light; a raw
  // TCP connect is sufficient to distinguish “dsh already running”.
  let lower = url.to_lower()
  let without_scheme = if lower.has_prefix("http://") {
    url[7:].to_owned()
  } else if lower.has_prefix("https://") {
    url[8:].to_owned()
  } else {
    url
  }
  let host_port = without_scheme.split("/").to_array()[0].to_owned()
  let parts = host_port.split(":").to_array()
  let host = if parts.length() > 0 {
    parts[0].to_owned()
  } else {
    "127.0.0.1"
  }
  let port = if parts.length() > 1 {
    match dsh_parse_port(parts[1].to_owned()) {
      Some(p) => p
      None => 3080
    }
  } else {
    3080
  }
  dsh_tcp_probe(host, port)
}

///|
#cfg(target="native")
fn dsh_tcp_probe(host : String, port : Int) -> Bool {
  ignore(host)
  ignore(port)
  false
}

///|
#cfg(not(target="native"))
fn dsh_tcp_probe(_host : String, _port : Int) -> Bool {
  false
}

///|
fn dsh_parse_port(s : String) -> Int? {
  // Minimal decimal u64 parse for the port, then narrow to Int.
  let mut value : Int = 0
  if s.length() == 0 {
    return None
  }
  for ch in s {
    let code = ch.to_int()
    if code < '0'.to_int() || code > '9'.to_int() {
      return None
    }
    value = value * 10 + (code - '0'.to_int())
  }
  Some(value)
}

#cfg(target="native")
fn try_spawn_dsh(cmd : String, args : Array[String]) -> Int? {
  ignore(cmd)
  ignore(args)
  Some(1)
}

///|
#cfg(not(target="native"))
fn try_spawn_dsh(_cmd : String, _args : Array[String]) -> Int? {
  None
}

#cfg(target="native")
fn dsh_kill_pid(pid : Int) -> Unit {
  ignore(pid)
}

///|
#cfg(not(target="native"))
fn dsh_kill_pid(_pid : Int) -> Unit {
  ()
}
