require "./spec_helper"

ALERTS_SUMMARY_PATH = "/JSON/alert/view/alertsSummary/"

describe Mzap do
  it "prints alert summary after wait completion" do
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
      when ALERTS_SUMMARY_PATH
        context.response.status_code = 200
        context.response.print(%({"alertsSummary":{"High":2,"Medium":5,"Low":10,"Informational":20}}))
      else
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://summary.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      stdout = stdout_io.to_s
      stdout.includes?("High: 2, Medium: 5, Low: 10, Informational: 20").should be_true
    ensure
      server.close
    end
  end

  it "does not print alert summary without wait mode" do
    server = TestServer.new

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://no-summary.test"]) do |target_file|
        options = Mzap::Options.new
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      paths = server.requests.map(&.path)
      paths.includes?(ALERTS_SUMMARY_PATH).should be_false
    ensure
      server.close
    end
  end

  it "handles alert summary API failure gracefully" do
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
      when ALERTS_SUMMARY_PATH
        context.response.status_code = 500
        context.response.print(%({"error":"internal error"}))
      else
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://summary-fail.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      stderr = stderr_io.to_s
      stderr.includes?("summary fetch failed").should be_true
    ensure
      server.close
    end
  end

  it "prints alert summary for passive scan" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::PSCAN_RECORDS_TO_SCAN
        context.response.status_code = 200
        context.response.print(%({"recordsToScan":"0"}))
      when ALERTS_SUMMARY_PATH
        context.response.status_code = 200
        context.response.print(%({"alertsSummary":{"High":1,"Medium":3,"Low":5,"Informational":8}}))
      else
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5)
      Mzap.passive_scan(server.url, options: options, reporter: reporter)

      stdout = stdout_io.to_s
      stdout.includes?("High: 1, Medium: 3, Low: 5, Informational: 8").should be_true
    ensure
      server.close
    end
  end
end
