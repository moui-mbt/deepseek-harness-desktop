///|
async fn[T] dsh_run_service_task(
  task : @services.ServiceTask[T],
) -> @services.ServiceTaskResult[T] {
  @async.with_timeout(5000, () => {
    let result : Ref[@services.ServiceTaskResult[T]?] = Ref(None)
    ignore(task.start(value => result.val = Some(value)))
    for ;; {
      match result.val {
        Some(value) => return value
        None => @async.sleep(1)
      }
    }
  })
}

///|
async fn dsh_find_free_port() -> Int {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  let port = server.addr.port()
  server.close()
  port
}

///|
async fn dsh_wait_for_probe(url : String, expected : Bool) -> Bool {
  for _ in 0..<100 {
    if dsh_probe_harness(url) == expected {
      return true
    }
    @async.sleep(50)
  }
  false
}

///|
#cfg(not(platform="windows"))
async test "async dsh service stops owned processes explicitly and at shutdown" {
  let port = dsh_find_free_port()
  let url = "http://127.0.0.1:\{port}"
  @async.with_task_group(group => {
    let dsh = service(group, dsh_cmd="python3", dsh_args=[
      "-m",
      "http.server",
      port.to_string(),
      "--bind",
      "127.0.0.1",
    ])
    assert_true(
      dsh_run_service_task(dsh.check(harness_url=url)) ==
      @services.ServiceTaskResult::Success(false),
    )
    assert_true(
      dsh_run_service_task(dsh.start(harness_url=url)) ==
      @services.ServiceTaskResult::Success(()),
    )
    assert_true(dsh_wait_for_probe(url, true))
    assert_true(
      dsh_run_service_task(dsh.stop(harness_url=url)) ==
      @services.ServiceTaskResult::Success(()),
    )
    assert_true(dsh_wait_for_probe(url, false))
  })

  let shutdown_port = dsh_find_free_port()
  let shutdown_url = "http://127.0.0.1:\{shutdown_port}"
  @async.with_task_group(group => {
    let dsh = service(group, dsh_cmd="python3", dsh_args=[
      "-m",
      "http.server",
      shutdown_port.to_string(),
      "--bind",
      "127.0.0.1",
    ])
    assert_true(
      dsh_run_service_task(dsh.start(harness_url=shutdown_url)) ==
      @services.ServiceTaskResult::Success(()),
    )
    assert_true(dsh_wait_for_probe(shutdown_url, true))
  })
  assert_true(dsh_wait_for_probe(shutdown_url, false))
}

///|
#cfg(not(platform="windows"))
async test "async dsh service never stops an external process" {
  let port = dsh_find_free_port()
  let url = "http://127.0.0.1:\{port}"
  @async.with_task_group(group => {
    let _external = @process.spawn(
      group,
      "python3",
      ["-m", "http.server", port.to_string(), "--bind", "127.0.0.1"],
      cancel_handler=@process.graceful_cancel(timeout=500),
      no_wait=true,
    )
    assert_true(dsh_wait_for_probe(url, true))
    let dsh = service(group)
    assert_true(
      dsh_run_service_task(dsh.start(harness_url=url)) ==
      @services.ServiceTaskResult::Success(()),
    )
    match dsh_run_service_task(dsh.stop(harness_url=url)) {
      @services.ServiceTaskResult::Failure(error) =>
        inspect(error.code, content="dsh-not-owned")
      _ => fail("expected external DSH stop to be rejected")
    }
    assert_true(dsh_probe_harness(url))
  })
  assert_true(dsh_wait_for_probe(url, false))
}

///|
async test "async dsh service reports a missing command" {
  let port = dsh_find_free_port()
  let url = "http://127.0.0.1:\{port}"
  @async.with_task_group(group => {
    let dsh = service(group, dsh_cmd="definitely-not-a-real-dsh-command", dsh_args=[
      "web",
    ])
    match dsh_run_service_task(dsh.start(harness_url=url)) {
      @services.ServiceTaskResult::Failure(error) => {
        inspect(error.code, content="dsh-spawn-failed")
        assert_false(error.message.is_empty())
      }
      _ => fail("expected the missing command to fail")
    }
  })
}

///|
test "dsh endpoint derives local host and port" {
  guard dsh_endpoint("http://127.0.0.1:3080/path") is Some(endpoint) else {
    fail("expected a parsed endpoint")
  }
  inspect(endpoint.host, content="127.0.0.1")
  inspect(endpoint.port, content="3080")
  assert_true(endpoint.is_local)
  guard dsh_endpoint("https://localhost/") is Some(secure) else {
    fail("expected a parsed secure endpoint")
  }
  inspect(secure.port, content="443")
  assert_true(secure.is_local)
}

///|
test "dsh endpoint supports loopback IPv6 and rejects invalid ports" {
  guard dsh_endpoint("http://[::1]:4080/") is Some(endpoint) else {
    fail("expected an IPv6 endpoint")
  }
  inspect(endpoint.host, content="::1")
  inspect(endpoint.port, content="4080")
  assert_true(endpoint.is_local)
  assert_true(dsh_endpoint("http://127.0.0.1:0") is None)
  assert_true(dsh_endpoint("http://127.0.0.1:70000") is None)
  assert_true(dsh_endpoint("not-a-url") is None)
}
