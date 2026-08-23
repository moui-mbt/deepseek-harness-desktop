///|
priv struct DshEndpoint {
  host : String
  port : Int
  is_local : Bool
}

///|
/// Build a native DSH service whose process and operation tasks are owned by
/// the application task group. A DSH server detected before `start` remains
/// external and is never terminated by this service.
pub fn[X] service(
  group : @async.TaskGroup[X],
  dsh_cmd? : String = "dsh",
  dsh_args? : Array[String] = [],
) -> @app.DshService {
  let process_ref : Ref[@process.Process?] = Ref(None)
  let configured_args = dsh_args.copy()
  @app.DshService::new(
    check=harness_url => {
      dsh_service_task(
        group,
        key="dsh:check:native",
        error_code="dsh-check-failed",
        () => {
          match process_ref.val {
            Some(process) if !dsh_process_running(process) => {
              process_ref.val = None
              return @services.ServiceTaskResult::Failure(
                @services.ServiceError::new(
                  code="dsh-exited-before-ready",
                  message="DSH process exited before the Harness endpoint became ready",
                ),
              )
            }
            _ => ()
          }
          @services.ServiceTaskResult::Success(dsh_probe_harness(harness_url))
        },
      )
    },
    start=harness_url => {
      dsh_service_task(
        group,
        key="dsh:start:native",
        error_code="dsh-spawn-failed",
        () => {
          if dsh_probe_harness(harness_url) {
            return @services.ServiceTaskResult::Success(())
          }
          match process_ref.val {
            Some(process) if dsh_process_running(process) =>
              return @services.ServiceTaskResult::Success(())
            _ => process_ref.val = None
          }
          match dsh_endpoint(harness_url) {
            None =>
              @services.ServiceTaskResult::Failure(
                @services.ServiceError::new(
                  code="dsh-invalid-url",
                  message="cannot derive a DSH host and port from " +
                    harness_url,
                ),
              )
            Some(endpoint) if configured_args.is_empty() && !endpoint.is_local =>
              @services.ServiceTaskResult::Failure(
                @services.ServiceError::new(
                  code="dsh-non-local-url",
                  message="refusing to start a local DSH process for remote host " +
                    endpoint.host,
                ),
              )
            Some(endpoint) => {
              let args = if configured_args.is_empty() {
                [
                  "web",
                  "--host",
                  endpoint.host,
                  "--port",
                  endpoint.port.to_string(),
                ]
              } else {
                configured_args
              }
              try {
                let command = dsh_resolve_command(dsh_cmd)
                let process = @process.spawn(
                  group,
                  command,
                  args,
                  no_console_window=true,
                  cancel_handler=@process.graceful_cancel(timeout=2000),
                  no_wait=true,
                )
                process_ref.val = Some(process)
                @services.ServiceTaskResult::Success(())
              } catch {
                error if @async.is_being_cancelled() => raise error
                error =>
                  @services.ServiceTaskResult::Failure(
                    @services.ServiceError::new(
                      code="dsh-spawn-failed",
                      message="failed to spawn " + dsh_cmd + ": \{error}",
                    ),
                  )
              }
            }
          }
        },
      )
    },
    stop=harness_url => {
      dsh_service_task(
        group,
        key="dsh:stop:native",
        error_code="dsh-stop-failed",
        () => {
          match process_ref.val {
            Some(process) => {
              dsh_stop_owned_process(process)
              process_ref.val = None
              @services.ServiceTaskResult::Success(())
            }
            None if dsh_probe_harness(harness_url) =>
              @services.ServiceTaskResult::Failure(
                @services.ServiceError::new(
                  code="dsh-not-owned",
                  message="DSH is reachable but was not started by this application",
                ),
              )
            None => @services.ServiceTaskResult::Success(())
          }
        },
      )
    },
  )
}

///|
fn[X, T] dsh_service_task(
  group : @async.TaskGroup[X],
  key~ : String,
  error_code~ : String,
  run : async () -> @services.ServiceTaskResult[T],
) -> @services.ServiceTask[T] {
  @services.ServiceTask::new(key~, start=complete => {
    let task = group.spawn(no_wait=true, allow_failure=true, () => {
      complete(run()) catch {
        _ if @async.is_being_cancelled() => ()
        error =>
          complete(
            @services.ServiceTaskResult::Failure(
              @services.ServiceError::new(code=error_code, message="\{error}"),
            ),
          )
      }
    })
    Some(() => task.cancel())
  })
}

///|
#cfg(platform="windows")
async fn dsh_resolve_command(command : String) -> String {
  command
}

///|
#cfg(not(platform="windows"))
async fn dsh_resolve_command(command : String) -> String {
  if command.contains("/") {
    return command
  }
  let directories : Array[String] = []
  match @env.get_env_var("PATH") {
    Some(path) =>
      for directory in path.split(":") {
        if directory != "" {
          directories.push(directory.to_owned())
        }
      }
    None => ()
  }
  match @env.get_env_var("HOME") {
    Some(home) if home != "" => {
      directories.push(home + "/.local/bin")
      directories.push(home + "/.local/share/pnpm")
      directories.push(home + "/.bun/bin")
      directories.push(home + "/.npm-global/bin")
    }
    _ => ()
  }
  directories.push("/opt/homebrew/bin")
  directories.push("/usr/local/bin")
  directories.push("/usr/bin")
  directories.push("/bin")
  for directory in directories {
    let candidate = directory + "/" + command
    if (@fs.can_execute(candidate) catch { _ => false }) {
      return candidate
    }
  }
  command
}

///|
fn dsh_process_running(process : @process.Process) -> Bool {
  match (process.try_wait() catch { _ => Some(-1) }) {
    None => true
    Some(_) => false
  }
}

///|
async fn dsh_stop_owned_process(process : @process.Process) -> Unit {
  match process.try_wait() {
    Some(_) => ()
    None => {
      process.cancel()
      ignore(process.wait()) catch {
        error if @async.is_cancellation_error(error) &&
          !@async.is_being_cancelled() => ()
        error => raise error
      }
    }
  }
}

///|
async fn dsh_probe_harness(url : String) -> Bool {
  match dsh_endpoint(url) {
    Some(endpoint) => dsh_tcp_probe_host(endpoint.host, endpoint.port)
    None => false
  }
}

///|
async fn dsh_tcp_probe_host(host : String, port : Int) -> Bool {
  try {
    let connection = @async.with_timeout(500, () => {
      @socket.Tcp::connect_to_host(host, port~)
    })
    connection.close()
    true
  } catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
}

///|
fn dsh_endpoint(url : String) -> DshEndpoint? {
  let lower = url.to_lower()
  let without_scheme = if lower.has_prefix("http://") {
    url[7:].to_owned()
  } else if lower.has_prefix("https://") {
    url[8:].to_owned()
  } else {
    return None
  }
  let host_port = without_scheme.split("/").to_array()[0].to_owned()
  let (host, port) = if host_port.has_prefix("[") {
    let bracket_parts = host_port.split("]").to_array()
    if bracket_parts.length() != 2 {
      return None
    }
    let host = bracket_parts[0][1:].to_owned()
    let suffix = bracket_parts[1].to_owned()
    let port = if suffix.has_prefix(":") {
      dsh_parse_port(suffix[1:].to_owned())
    } else if suffix == "" {
      Some(if lower.has_prefix("https://") { 443 } else { 80 })
    } else {
      None
    }
    match port {
      Some(port) => (host, port)
      None => return None
    }
  } else {
    let parts = host_port.split(":").to_array()
    if parts.length() > 2 || parts.length() == 0 {
      return None
    }
    let host = parts[0].to_owned()
    let port = if parts.length() == 2 {
      dsh_parse_port(parts[1].to_owned())
    } else {
      Some(if lower.has_prefix("https://") { 443 } else { 80 })
    }
    match port {
      Some(port) => (host, port)
      None => return None
    }
  }
  if host == "" || port <= 0 || port > 65535 {
    return None
  }
  let normalized_host = host.to_lower()
  Some({
    host,
    port,
    is_local: normalized_host == "127.0.0.1" ||
    normalized_host == "localhost" ||
    normalized_host == "::1",
  })
}

///|
fn dsh_parse_port(s : String) -> Int? {
  let mut value = 0
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
  if value <= 0 || value > 65535 {
    None
  } else {
    Some(value)
  }
}
