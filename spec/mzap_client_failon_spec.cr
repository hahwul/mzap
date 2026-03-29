require "./spec_helper"

ALERTS_VIEW_PATH = "/JSON/alert/view/alerts/"

describe Mzap do
  it "returns true when alerts exceed fail-on threshold" do
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
        context.response.print(%({"status":"100"}))
      when ALERTS_VIEW_PATH
        context.response.status_code = 200
        context.response.print(%({"alerts":[{"alert":"XSS","risk":"High","confidence":"Medium"}]}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://failon.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, fail_on: "medium")
        result = Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
        result.should be_true
      end

      stderr = stderr_io.to_s
      stderr.includes?("1 alert(s) at or above medium level").should be_true
    ensure
      server.close
    end
  end

  it "returns false when no alerts exceed fail-on threshold" do
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
        context.response.print(%({"status":"100"}))
      when ALERTS_VIEW_PATH
        context.response.status_code = 200
        context.response.print(%({"alerts":[{"alert":"Info Leak","risk":"Informational","confidence":"Low"}]}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://failon-pass.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, fail_on: "high")
        result = Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
        result.should be_false
      end

      stdout = stdout_io.to_s
      stdout.includes?("no alerts at or above high level").should be_true
    ensure
      server.close
    end
  end

  it "returns exit code 1 via CLI when fail-on is triggered" do
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
        context.response.print(%({"status":"100"}))
      when ALERTS_VIEW_PATH
        context.response.status_code = 200
        context.response.print(%({"alerts":[{"alert":"SQLi","risk":"High"}]}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      with_target_file(["https://cli-failon.test"]) do |target_file|
        code = Mzap::CLI.run(
          ["spider", "--urls", target_file, "--apis", server.url, "--fail-on", "low"],
          stdout_io,
          stderr_io
        )
        code.should eq(1)
      end
    ensure
      server.close
    end
  end

  it "returns exit code 0 via CLI when fail-on is not triggered" do
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
        context.response.print(%({"status":"100"}))
      when ALERTS_VIEW_PATH
        context.response.status_code = 200
        context.response.print(%({"alerts":[]}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      with_target_file(["https://cli-failon-pass.test"]) do |target_file|
        code = Mzap::CLI.run(
          ["spider", "--urls", target_file, "--apis", server.url, "--fail-on", "high"],
          stdout_io,
          stderr_io
        )
        code.should eq(0)
      end
    ensure
      server.close
    end
  end

  it "rejects invalid --fail-on value" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    code = Mzap::CLI.run(["spider", "--urls", "targets.txt", "--fail-on", "critical"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("--fail-on supports only informational, low, medium, or high").should be_true
  end

  it "implies wait mode when --fail-on is set" do
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
        context.response.print(%({"status":"100"}))
      when ALERTS_VIEW_PATH
        context.response.status_code = 200
        context.response.print(%({"alerts":[]}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      with_target_file(["https://wait-implied.test"]) do |target_file|
        code = Mzap::CLI.run(
          ["spider", "--urls", target_file, "--apis", server.url, "--fail-on", "high"],
          stdout_io,
          stderr_io
        )
        code.should eq(0)
      end

      paths = server.requests.map(&.path)
      paths.includes?(Mzap::Client::SPIDER_STATUS).should be_true
      paths.includes?(ALERTS_VIEW_PATH).should be_true
    ensure
      server.close
    end
  end
end
