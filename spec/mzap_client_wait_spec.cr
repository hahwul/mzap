require "./spec_helper"

describe Mzap do
  it "warns timeout when wait exceeds timeout seconds" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"3"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"1"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://timeout.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 1, 1)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      stderr = stderr_io.to_s
      stderr.includes?("[wait]").should be_true
      stderr.includes?("timeout").should be_true
    ensure
      server.close
    end
  end

  it "logs wait status check failure reason and wait summary" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"6"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 500
        context.response.print(%({"error":"status error"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://wait-error.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 1, 1)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      stderr = stderr_io.to_s
      stdout = stdout_io.to_s
      stderr.includes?("status check failed (HTTP 500)").should be_true
      stderr.includes?("timeout").should be_true
      stdout.includes?("scan_completed=0/1").should be_true
      stdout.includes?("timed_out=true").should be_true
      stdout.includes?("poll_failures=").should be_true
    ensure
      server.close
    end
  end

  it "waits for ajax spider completion when status leaves running state" do
    status_calls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::AJAX_SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"1"}))
      when Mzap::Client::AJAX_STATUS
        status_calls += 1
        context.response.status_code = 200
        if status_calls == 1
          context.response.print(%({"status":"running"}))
        else
          context.response.print(%({"status":"stopped"}))
        end
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://ajax-wait.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.ajax_spider(target_file, server.url, options, reporter)
      end

      paths = server.requests.map(&.path)
      paths.includes?(Mzap::Client::AJAX_STATUS).should be_true
      stdout = stdout_io.to_s
      stdout.includes?("ajax_completed=1/1").should be_true
      stdout.includes?("timed_out=false").should be_true
    ensure
      server.close
    end
  end

  it "uses scanId key for wait polling query when scan response provides scanId" do
    status_queries = [] of String?
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scanId":"42"}))
      when Mzap::Client::SPIDER_STATUS
        status_queries << context.request.query
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://scan-id.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      status_queries.size.should eq(1)
      query = HTTP::Params.parse(status_queries.first || "")
      query["scanId"].should eq("42")
    ensure
      server.close
    end
  end

  it "warns about missing scan id and skips wait polling for that target" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"message":"started"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://missing-scan-id.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      paths = server.requests.map(&.path)
      paths.includes?(Mzap::Client::SPIDER_STATUS).should be_false
      stderr_io.to_s.includes?("missing scan id (wait disabled for target)").should be_true
      stdout_io.to_s.includes?("[wait] start").should be_false
    ensure
      server.close
    end
  end

  it "logs missing status value as wait poll failure reason" do
    status_calls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"7"}))
      when Mzap::Client::SPIDER_STATUS
        status_calls += 1
        context.response.status_code = 200
        if status_calls == 1
          context.response.print(%({}))
        else
          context.response.print(%({"status":"100"}))
        end
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://missing-status.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      stderr = stderr_io.to_s
      stdout = stdout_io.to_s
      stderr.includes?("status check failed (missing status value)").should be_true
      stdout.includes?("timed_out=false").should be_true
    ensure
      server.close
    end
  end

  it "accepts numeric id key in scan response for wait polling" do
    status_queries = [] of String?
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"id":77}))
      when Mzap::Client::SPIDER_STATUS
        status_queries << context.request.query
        context.response.status_code = 200
        context.response.print(%({"status":100}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://numeric-id.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      status_queries.size.should eq(1)
      params = HTTP::Params.parse(status_queries.first || "")
      params["scanId"].should eq("77")
    ensure
      server.close
    end
  end

  it "treats boolean wait status values as completion" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"19"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":true}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://boolean-status.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      stdout = stdout_io.to_s
      stdout.includes?("scan_completed=1/1").should be_true
      stdout.includes?("timed_out=false").should be_true
      stderr_io.to_s.includes?("status check failed").should be_false
    ensure
      server.close
    end
  end

  it "deduplicates repeated wait poll failure warnings for the same reason" do
    status_calls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"23"}))
      when Mzap::Client::SPIDER_STATUS
        status_calls += 1
        if status_calls <= 2
          context.response.status_code = 500
          context.response.print(%({"error":"status error"}))
        else
          context.response.status_code = 200
          context.response.print(%({"status":"100"}))
        end
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://dedupe-wait-error.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      stderr = stderr_io.to_s
      stdout = stdout_io.to_s
      stderr.scan(/status check failed \(HTTP 500\)/).size.should eq(1)
      stdout.includes?("poll_failures=2").should be_true
      stdout.includes?("timed_out=false").should be_true
    ensure
      server.close
    end
  end

  it "uses scanid key for active scan wait polling query" do
    status_queries = [] of String?
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::ASCAN_API
        context.response.status_code = 200
        context.response.print(%({"scanid":"91"}))
      when Mzap::Client::ASCAN_STATUS
        status_queries << context.request.query
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://ascan-scanid.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.active_scan(target_file, server.url, options, reporter)
      end

      status_queries.size.should eq(1)
      query = HTTP::Params.parse(status_queries.first || "")
      query["scanId"].should eq("91")
    ensure
      server.close
    end
  end

  it "warns and skips wait polling when scan response has no recognizable scan id" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"message":"started"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://invalid-json-scan.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      paths = server.requests.map(&.path)
      paths.includes?(Mzap::Client::SPIDER_STATUS).should be_false
      stderr_io.to_s.includes?("missing scan id (wait disabled for target)").should be_true
      stdout_io.to_s.includes?("[wait] start").should be_false
    ensure
      server.close
    end
  end

  it "treats invalid status JSON as poll failure in wait polling" do
    status_calls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"88"}))
      when Mzap::Client::SPIDER_STATUS
        status_calls += 1
        context.response.status_code = 200
        if status_calls == 1
          context.response.print("{broken-json")
        else
          context.response.print(%({"status":"100"}))
        end
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://invalid-status-json.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      stderr_io.to_s.includes?("status check failed").should be_true
      stdout_io.to_s.includes?("timed_out=false").should be_true
    ensure
      server.close
    end
  end

  it "waits for active scan completion using ascan status endpoint" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::ASCAN_API
        context.response.status_code = 200
        context.response.print(%({"scan":"33"}))
      when Mzap::Client::ASCAN_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://ascan-wait.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.active_scan(target_file, server.url, options, reporter)
      end

      paths = server.requests.map(&.path)
      paths.includes?(Mzap::Client::ASCAN_STATUS).should be_true
      stdout_io.to_s.includes?("scan_completed=1/1").should be_true
    ensure
      server.close
    end
  end

  it "deduplicates repeated ajax wait failure warnings for the same reason" do
    status_calls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::AJAX_SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"1"}))
      when Mzap::Client::AJAX_STATUS
        status_calls += 1
        if status_calls <= 2
          context.response.status_code = 500
          context.response.print(%({"error":"status error"}))
        else
          context.response.status_code = 200
          context.response.print(%({"status":"stopped"}))
        end
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://ajax-dedupe-fail.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.ajax_spider(target_file, server.url, options, reporter)
      end

      stderr = stderr_io.to_s
      stdout = stdout_io.to_s
      stderr.scan(/status check failed \(HTTP 500\)/).size.should eq(1)
      stdout.includes?("ajax_completed=1/1").should be_true
      stdout.includes?("poll_failures=2").should be_true
    ensure
      server.close
    end
  end

  it "polls ajax status once per host even with multiple targets" do
    ajax_status_calls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::AJAX_SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"1"}))
      when Mzap::Client::AJAX_STATUS
        ajax_status_calls += 1
        context.response.status_code = 200
        context.response.print(%({"status":"stopped"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://ajax-one.test", "https://ajax-two.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.ajax_spider(target_file, server.url, options, reporter)
      end

      ajax_status_calls.should eq(1)
    ensure
      server.close
    end
  end

  it "treats in_progress as running and completes when status changes" do
    status_calls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"77"}))
      when Mzap::Client::SPIDER_STATUS
        status_calls += 1
        context.response.status_code = 200
        if status_calls == 1
          context.response.print(%({"status":"in_progress"}))
        else
          context.response.print(%({"status":"paused"}))
        end
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://status-change.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      status_calls.should eq(2)
      stdout = stdout_io.to_s
      stdout.includes?("scan_completed=1/1").should be_true
      stdout.includes?("timed_out=false").should be_true
      stderr_io.to_s.includes?("status check failed").should be_false
    ensure
      server.close
    end
  end

  it "handles float status value for wait polling" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"50"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":100.0}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://float-status.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      stdout = stdout_io.to_s
      stdout.includes?("scan_completed=1/1").should be_true
      stdout.includes?("timed_out=false").should be_true
    ensure
      server.close
    end
  end

  it "warns when scan ends with error status and still counts as completed" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"99"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"error"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://error-status.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      stderr = stderr_io.to_s
      stdout = stdout_io.to_s
      stderr.includes?("completed with error").should be_true
      stderr.includes?("scan ended with status: error").should be_true
      stdout.includes?("scan_completed=1/1").should be_true
      stdout.includes?("timed_out=false").should be_true
    ensure
      server.close
    end
  end

  it "treats busy, started, and inprogress as running and waits for completion" do
    {"busy", "started", "inprogress"}.each do |running_status|
      status_calls = 0
      server = TestServer.new(->(context : HTTP::Server::Context) do
        case context.request.path
        when Mzap::Client::ACCESS_API
          context.response.status_code = 200
          context.response.print(%({"ok":"true"}))
        when Mzap::Client::SPIDER_API
          context.response.status_code = 200
          context.response.print(%({"scan":"88"}))
        when Mzap::Client::SPIDER_STATUS
          status_calls += 1
          context.response.status_code = 200
          if status_calls == 1
            context.response.print(%({"status":"#{running_status}"}))
          else
            context.response.print(%({"status":"100"}))
          end
        else
          context.response.status_code = 404
          context.response.print(%({"error":"not found"}))
        end
      end)

      begin
        stdout_io = IO::Memory.new
        stderr_io = IO::Memory.new
        reporter = Mzap::Reporter.new(stdout_io, stderr_io)
        with_target_file(["https://#{running_status}-status.test"]) do |target_file|
          options = Mzap::Options.new("", target_file, true, 0, 5)
          Mzap.spider(target_file, server.url, options, reporter)
        end

        status_calls.should eq(2)
        stderr_io.to_s.includes?("status check failed").should be_false
      ensure
        server.close
      end
    end
  end

  it "gracefully handles invalid JSON in status response" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"1"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print("invalid json string {]}")
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://json-error.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 1)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      stderr = stderr_io.to_s
      stderr.includes?("status check failed").should be_true
    ensure
      server.close
    end
  end
end
