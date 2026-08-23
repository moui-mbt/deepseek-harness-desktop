///|
test "dsh lifecycle surfaces process errors" {
  let starting = update(
    update(
      Model::new(capability=WebViewCapability::available()),
      DshCheckResult(@services.ServiceTaskResult::Success(false)),
    ),
    StartDshWeb,
  )
  let failed_start = update(
    starting,
    DshStartResult(
      @services.ServiceTaskResult::Failure(
        @services.ServiceError::new(code="spawn", message="command missing"),
      ),
    ),
  )
  assert_true(failed_start.dsh_web_status == DshWebStatus::Stopped)
  inspect(failed_start.status, content="failed to start DSH: command missing")
  let running = update(
    { ..starting, dsh_web_status: DshWebStatus::Stopping },
    DshStopResult(
      @services.ServiceTaskResult::Failure(
        @services.ServiceError::new(code="stop", message="not owned"),
      ),
    ),
  )
  assert_true(running.dsh_web_status == DshWebStatus::Running)
  inspect(running.status, content="failed to stop DSH: not owned")
}
