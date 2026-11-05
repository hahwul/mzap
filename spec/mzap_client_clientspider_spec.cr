require "./spec_helper"

describe Mzap do
  it "runs client spider scan endpoint after accessing the url" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 200
      if context.request.path == Mzap::Client::CLIENT_SPIDER_API
        context.response.print(%({"scan":"3"}))
      else
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://spa.test"]) do |target_file|
        options = Mzap::Options.new
        Mzap.client_spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      requests = server.requests
      requests.size.should eq(2)
      requests[0].path.should eq(Mzap::Client::ACCESS_API)
      requests[1].path.should eq(Mzap::Client::CLIENT_SPIDER_API)
      HTTP::Params.parse(requests[1].query || "")["url"].should eq("https://spa.test")
    ensure
      server.close
    end
  end

  it "waits for client spider completion using percentage status" do
    polls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 200
      case context.request.path
      when Mzap::Client::CLIENT_SPIDER_API
        context.response.print(%({"scan":"5"}))
      when Mzap::Client::CLIENT_SPIDER_STAT
        polls += 1
        context.response.print(polls >= 2 ? %({"status":"100"}) : %({"status":"40"}))
      else
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, IO::Memory.new)
      with_target_file(["https://spa.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 1)
        Mzap.client_spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      status_request = server.requests.find { |r| r.path == Mzap::Client::CLIENT_SPIDER_STAT }
      status_request.should_not be_nil
      HTTP::Params.parse(status_request.not_nil!.query || "")["scanId"].should eq("5")
      stdout_io.to_s.includes?("complete").should be_true
    ensure
      server.close
    end
  end

  it "stops running client spider scans until ZAP rejects a scan id as unknown" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      scan_id = HTTP::Params.parse(context.request.query || "")["scanId"]?.try(&.to_i?) || -1
      if scan_id < 0 || scan_id >= 3
        context.response.status_code = 400
        context.response.print(%({"code":"illegal_parameter","message":"Provided parameter has illegal or unrecognized value (scanId)."}))
      elsif context.request.path == Mzap::Client::CLIENT_SPIDER_STAT
        context.response.status_code = 200
        context.response.print(scan_id == 1 ? %({"status":"100"}) : %({"status":"42"}))
      else
        context.response.status_code = 200
        context.response.print(%({"Result":"OK"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      options = Mzap::Options.new(api_key: "stop-key")
      Mzap.stop_client_spider(server.url, options: options, reporter: reporter)

      stops = server.requests.select { |r| r.path == Mzap::Client::CLIENT_SPIDER_STOP }
      stops.map { |r| HTTP::Params.parse(r.query || "")["scanId"] }.should eq(["0", "2"])
      server.requests.last.path.should eq(Mzap::Client::CLIENT_SPIDER_STAT)
      HTTP::Params.parse(server.requests.last.query || "")["scanId"].should eq("3")
      stdout_io.to_s.includes?("summary success=1 failed=0").should be_true
      stderr_io.to_s.includes?("error (stop)").should be_false
    ensure
      server.close
    end
  end

  it "gives up on client spider stop when the server never rejects a scan id" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 200
      context.response.print(%({"status":"100"}))
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      Mzap.stop_client_spider(server.url, options: Mzap::Options.new, reporter: reporter)

      server.requests.size.should eq(Mzap::Client::CLIENT_SPIDER_STOP_MAX_IDS)
      stderr_io.to_s.includes?("error (stop) (no unknown client spider scan id").should be_true
      stdout_io.to_s.includes?("summary success=0 failed=1").should be_true
    ensure
      server.close
    end
  end

  it "reports client spider stop failures other than an unknown scan id" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 500
      context.response.print(%({"code":"internal_error"}))
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      Mzap.stop_client_spider(server.url, options: Mzap::Options.new, reporter: reporter)

      server.requests.size.should eq(1)
      stderr_io.to_s.includes?("error (stop) (HTTP 500)").should be_true
      stdout_io.to_s.includes?("summary success=0 failed=1").should be_true
    ensure
      server.close
    end
  end
end
