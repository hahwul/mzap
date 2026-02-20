require "./spec_helper"
require "http/params"
require "http/server"

record CapturedRequest, path : String, query : String?, api_key : String?

class TestServer
  getter url : String

  def initialize(@handler : Proc(HTTP::Server::Context, Nil)? = nil)
    @requests = [] of CapturedRequest
    @lock = Mutex.new
    @server = HTTP::Server.new do |context|
      request = context.request
      @lock.synchronize do
        @requests << CapturedRequest.new(
          request.path,
          request.query,
          request.headers["X-ZAP-API-Key"]?
        )
      end
      if @handler
        @handler.not_nil!.call(context)
      else
        context.response.status_code = 200
        context.response.print("ok")
      end
    end

    address = @server.bind_tcp("127.0.0.1", 0)
    @url = "http://#{address.address}:#{address.port}"
    @done = Channel(Nil).new

    spawn do
      begin
        @server.listen
      rescue ex : Exception
      ensure
        @done.send(nil)
      end
    end
  end

  def requests : Array(CapturedRequest)
    @lock.synchronize { @requests.dup }
  end

  def close : Nil
    @server.close
    @done.receive
  end
end

private def with_target_file(lines : Array(String), &block : String ->)
  path = File.tempname("mzap-targets")
  File.write(path, lines.join("\n") + "\n")
  begin
    yield path
  ensure
    File.delete(path) if File.exists?(path)
  end
end

private def stop_path(path : String) : String
  path.ends_with?("?") ? path[0...-1] : path
end

private def sanitized_host_for_report(value : String) : String
  normalized = value.gsub(/[^a-zA-Z0-9]+/, "-").gsub(/^-+/, "").gsub(/-+$/, "")
  normalized.empty? ? "host" : normalized
end

describe Mzap do
  it "runs spider scan with round robin host selection and API key header" do
    server1 = TestServer.new
    server2 = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://a.test", "https://b.test", "https://c.test"]) do |target_file|
        options = Mzap::Options.new("test-key", target_file)
        Mzap.spider(target_file, "#{server1.url},#{server2.url}", options, reporter)
      end

      requests1 = server1.requests
      requests2 = server2.requests

      requests1.size.should eq(4)
      requests2.size.should eq(2)

      requests1[0].path.should eq(Mzap::Client::ACCESS_API)
      HTTP::Params.parse(requests1[0].query || "")["url"].should eq("https://a.test")
      requests1[1].path.should eq(Mzap::Client::SPIDER_API)
      HTTP::Params.parse(requests1[1].query || "")["url"].should eq("https://a.test")

      requests2[0].path.should eq(Mzap::Client::ACCESS_API)
      HTTP::Params.parse(requests2[0].query || "")["url"].should eq("https://b.test")
      requests2[1].path.should eq(Mzap::Client::SPIDER_API)
      HTTP::Params.parse(requests2[1].query || "")["url"].should eq("https://b.test")

      requests1[2].path.should eq(Mzap::Client::ACCESS_API)
      HTTP::Params.parse(requests1[2].query || "")["url"].should eq("https://c.test")
      requests1[3].path.should eq(Mzap::Client::SPIDER_API)
      HTTP::Params.parse(requests1[3].query || "")["url"].should eq("https://c.test")

      (requests1 + requests2).each do |request|
        request.api_key.should eq("test-key")
      end
    ensure
      server1.close
      server2.close
    end
  end

  it "runs ajax spider scan endpoint" do
    server = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://ajax.test"]) do |target_file|
        options = Mzap::Options.new("", target_file)
        Mzap.ajax_spider(target_file, server.url, options, reporter)
      end

      requests = server.requests
      requests.size.should eq(2)
      requests[0].path.should eq(Mzap::Client::ACCESS_API)
      requests[1].path.should eq(Mzap::Client::AJAX_SPIDER_API)
    ensure
      server.close
    end
  end

  it "runs active scan endpoint" do
    server = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://ascan.test"]) do |target_file|
        options = Mzap::Options.new("", target_file)
        Mzap.active_scan(target_file, server.url, options, reporter)
      end

      requests = server.requests
      requests.size.should eq(2)
      requests[0].path.should eq(Mzap::Client::ACCESS_API)
      requests[1].path.should eq(Mzap::Client::ASCAN_API)
    ensure
      server.close
    end
  end

  it "ignores empty and comment lines and trims API hosts" do
    server1 = TestServer.new
    server2 = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["  https://a.test  ", "", "   # comment", "https://b.test", "   "]) do |target_file|
        options = Mzap::Options.new("", target_file)
        Mzap.spider(target_file, " #{server1.url} , #{server2.url} ", options, reporter)
      end

      requests1 = server1.requests
      requests2 = server2.requests
      requests1.size.should eq(2)
      requests2.size.should eq(2)

      HTTP::Params.parse(requests1[0].query || "")["url"].should eq("https://a.test")
      HTTP::Params.parse(requests1[1].query || "")["url"].should eq("https://a.test")
      HTTP::Params.parse(requests2[0].query || "")["url"].should eq("https://b.test")
      HTTP::Params.parse(requests2[1].query || "")["url"].should eq("https://b.test")
    ensure
      server1.close
      server2.close
    end
  end

  it "warns and skips scan when target file has no valid entries" do
    server = TestServer.new

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["", "   ", "  # comment"]) do |target_file|
        options = Mzap::Options.new("", target_file)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      server.requests.should be_empty
      stderr_io.to_s.includes?("no targets loaded from file").should be_true
    ensure
      server.close
    end
  end

  it "treats non-2xx scan response as an error" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      if context.request.path == Mzap::Client::SPIDER_API
        context.response.status_code = 500
        context.response.print("error")
      else
        context.response.status_code = 200
        context.response.print("ok")
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://error.test"]) do |target_file|
        options = Mzap::Options.new("", target_file)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      stderr_io.to_s.includes?("error (scan)").should be_true
      stderr_io.to_s.includes?("HTTP 500").should be_true
      stdout_io.to_s.includes?("added").should be_false
    ensure
      server.close
    end
  end

  it "reports access endpoint failure details without aborting scan submission" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      if context.request.path == Mzap::Client::ACCESS_API
        context.response.status_code = 500
        context.response.print("access error")
      else
        context.response.status_code = 200
        context.response.print(%({"scan":"2"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://access-error.test"]) do |target_file|
        options = Mzap::Options.new("", target_file)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      stderr_io.to_s.includes?("error (access)").should be_true
      stderr_io.to_s.includes?("HTTP 500").should be_true
      stdout_io.to_s.includes?("added").should be_true
    ensure
      server.close
    end
  end

  it "prints scan summary counts for mixed scan results" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print("ok")
      when Mzap::Client::SPIDER_API
        target = HTTP::Params.parse(context.request.query || "")["url"]?
        if target == "https://bad.test"
          context.response.status_code = 500
          context.response.print("scan error")
        else
          context.response.status_code = 200
          context.response.print(%({"scan":"10"}))
        end
      else
        context.response.status_code = 404
        context.response.print("not found")
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://ok.test", "https://bad.test"]) do |target_file|
        options = Mzap::Options.new("", target_file)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      stdout = stdout_io.to_s
      stderr = stderr_io.to_s
      stdout.includes?("summary targets=2 success=1 scan_errors=1 access_errors=0").should be_true
      stderr.includes?("error (scan)").should be_true
      stderr.includes?("HTTP 500").should be_true
    ensure
      server.close
    end
  end

  it "warns when stop endpoint returns an error status" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 500
      context.response.print("error")
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      options = Mzap::Options.new("", "")
      Mzap.stop_spider(server.url, options, reporter)

      stderr_io.to_s.includes?("error (stop)").should be_true
      stderr_io.to_s.includes?("HTTP 500").should be_true
      stdout_io.to_s.includes?("stopped").should be_false
      stdout_io.to_s.includes?("summary success=0 failed=1").should be_true
    ensure
      server.close
    end
  end

  it "prints stop summary for mixed stop outcomes" do
    server_success = TestServer.new
    server_fail = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 500
      context.response.print("error")
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      options = Mzap::Options.new("", "")
      Mzap.stop_spider("#{server_success.url},#{server_fail.url}", options, reporter)

      stdout = stdout_io.to_s
      stderr = stderr_io.to_s
      stdout.includes?("summary success=1 failed=1").should be_true
      stderr.includes?("error (stop)").should be_true
      stderr.includes?("HTTP 500").should be_true
    ensure
      server_success.close
      server_fail.close
    end
  end

  it "sends stop requests for spider/ascan/ajaxspider" do
    server = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      options = Mzap::Options.new("stop-key", "")
      Mzap.stop_spider(server.url, options, reporter)
      Mzap.stop_ajax_spider(server.url, options, reporter)
      Mzap.stop_active_scan(server.url, options, reporter)

      requests = server.requests
      requests.size.should eq(3)
      requests[0].path.should eq(stop_path(Mzap::Client::SPIDER_STOP))
      requests[1].path.should eq(stop_path(Mzap::Client::AJAX_SPIDER_STOP))
      requests[2].path.should eq(stop_path(Mzap::Client::ASCAN_STOP))
      requests.each do |request|
        request.api_key.should eq("stop-key")
      end
    ensure
      server.close
    end
  end

  it "waits for spider completion and requests filtered html report" do
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
        if status_calls < 2
          context.response.print(%({"status":"50"}))
        else
          context.response.print(%({"status":"100"}))
        end
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print("not found")
      end
    end)

    report_path = "#{File.tempname("mzap-report")}.html"
    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://report.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 1, 10, "html", report_path)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      requests = server.requests
      paths = requests.map(&.path)
      paths.includes?(Mzap::Client::SPIDER_STATUS).should be_true
      paths.includes?(Mzap::Client::REPORT_GENERATE_API).should be_true

      report_request = requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should_not be_nil
      params = HTTP::Params.parse(report_request.not_nil!.query || "")
      params["sites"].should eq("https://report.test")
      params["template"].should eq("traditional-html")
      params["reportFileName"].should eq(File.basename(File.expand_path(report_path)))
      params["reportDir"].should eq(File.dirname(File.expand_path(report_path)))
    ensure
      File.delete(report_path) if File.exists?(report_path)
      server.close
    end
  end

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
        context.response.print("not found")
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
        context.response.print("status error")
      else
        context.response.status_code = 404
        context.response.print("not found")
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

  it "falls back to core html report when reports add-on endpoint is unavailable" do
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
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 404
        context.response.print("missing")
      when Mzap::Client::HTML_REPORT_API
        context.response.status_code = 200
        context.response.print("<html>fallback report</html>")
      else
        context.response.status_code = 404
        context.response.print("not found")
      end
    end)

    report_path = "#{File.tempname("mzap-report")}.html"
    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://fallback.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 1, 10, "html", report_path)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      requests = server.requests
      paths = requests.map(&.path)
      paths.includes?(Mzap::Client::REPORT_GENERATE_API).should be_true
      paths.includes?(Mzap::Client::HTML_REPORT_API).should be_true
      File.exists?(report_path).should be_true
      File.read(report_path).should eq("<html>fallback report</html>")
      reporter_output = stdout_io.to_s
      reporter_output.includes?("summary total=1 saved=0 fallback=1 failed=0").should be_true
    ensure
      File.delete(report_path) if File.exists?(report_path)
      server.close
    end
  end

  it "logs report failure reasons and report summary when all report endpoints fail" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"12"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 500
        context.response.print("filtered fail")
      when Mzap::Client::HTML_REPORT_API
        context.response.status_code = 500
        context.response.print("core fail")
      else
        context.response.status_code = 404
        context.response.print("not found")
      end
    end)

    report_path = "#{File.tempname("mzap-report")}.html"
    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://report-fail.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 1, 10, "html", report_path)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      stderr = stderr_io.to_s
      stdout = stdout_io.to_s
      stderr.includes?("filtered generation failed (HTTP 500)").should be_true
      stderr.includes?("error (HTTP 500)").should be_true
      stdout.includes?("summary total=1 saved=0 fallback=0 failed=1").should be_true
    ensure
      File.delete(report_path) if File.exists?(report_path)
      server.close
    end
  end

  it "normalizes report output extension to report format" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"9"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print("not found")
      end
    end)

    report_path = "#{File.tempname("mzap-report")}.html"
    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://ext.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 1, 10, "pdf", report_path)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      report_request = server.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should_not be_nil
      params = HTTP::Params.parse(report_request.not_nil!.query || "")
      full_path = File.expand_path(report_path)
      expected_name = "#{File.basename(full_path, File.extname(full_path))}.pdf"

      params["template"].should eq("traditional-pdf")
      params["reportFileName"].should eq(expected_name)
      params["reportDir"].should eq(File.dirname(full_path))
    ensure
      server.close
    end
  end

  it "generates host-specific report names for multiple api hosts" do
    handler = ->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"11"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print("not found")
      end
    end
    server1 = TestServer.new(handler)
    server2 = TestServer.new(handler)

    report_path = "#{File.tempname("mzap-report")}.html"
    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://one.test", "https://two.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 1, 10, "pdf", report_path)
        Mzap.spider(target_file, "#{server1.url},#{server2.url}", options, reporter)
      end

      full_path = File.expand_path(report_path)
      stem = File.basename(full_path, File.extname(full_path))
      expected1 = "#{stem}-#{sanitized_host_for_report(server1.url)}.pdf"
      expected2 = "#{stem}-#{sanitized_host_for_report(server2.url)}.pdf"
      expected_dir = File.dirname(full_path)

      report_request1 = server1.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request2 = server2.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request1.should_not be_nil
      report_request2.should_not be_nil

      params1 = HTTP::Params.parse(report_request1.not_nil!.query || "")
      params2 = HTTP::Params.parse(report_request2.not_nil!.query || "")
      params1["template"].should eq("traditional-pdf")
      params2["template"].should eq("traditional-pdf")
      params1["reportFileName"].should eq(expected1)
      params2["reportFileName"].should eq(expected2)
      params1["reportDir"].should eq(expected_dir)
      params2["reportDir"].should eq(expected_dir)
    ensure
      server1.close
      server2.close
    end
  end
end

describe Mzap::CLI do
  it "prints version and banner" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version"], stdout_io, stderr_io)
    code.should eq(0)
    stdout_io.to_s.includes?(Mzap::VERSION).should be_true
    stderr_io.to_s.includes?("MZAP").should be_true
  end

  it "prints missing urls message for spider command" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider"], stdout_io, stderr_io)
    code.should eq(1)
    stdout_io.to_s.includes?("Please input --urls flag").should be_true
  end

  it "prints missing mode message for stop command" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["stop"], stdout_io, stderr_io)
    code.should eq(1)
    stdout_io.to_s.includes?("Please input scanning mode for stop").should be_true
  end

  it "prints config file notice when --config is present and file exists" do
    config_path = File.tempname("mzap-config")
    File.write(config_path, "sample: true\n")

    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    begin
      Mzap::CLI.run(["version", "--config", config_path], stdout_io, stderr_io)
      stdout_io.to_s.includes?("Using config file: #{config_path}").should be_true
    ensure
      File.delete(config_path) if File.exists?(config_path)
    end
  end

  it "runs stop all via CLI for all stop endpoints" do
    server = TestServer.new
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    begin
      Mzap::CLI.run(["stop", "all", "--apis", server.url, "--apikey", "cli-key"], stdout_io, stderr_io)

      paths = server.requests.map(&.path)
      paths.should eq(
        [
          stop_path(Mzap::Client::SPIDER_STOP),
          stop_path(Mzap::Client::AJAX_SPIDER_STOP),
          stop_path(Mzap::Client::ASCAN_STOP),
        ]
      )
      server.requests.each do |request|
        request.api_key.should eq("cli-key")
      end
    ensure
      server.close
    end
  end

  it "returns error for invalid stop mode" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["stop", "invalid"], stdout_io, stderr_io)
    code.should eq(1)
    stdout_io.to_s.includes?("spider/ascan/ajaxspider/all").should be_true
  end

  it "returns error for unknown command" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["unknown-command"], stdout_io, stderr_io)
    code.should eq(1)
    stdout_io.to_s.includes?("Usage:").should be_true
  end

  it "returns error for empty API host list" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    config_path = File.tempname("mzap-targets")
    File.write(config_path, "https://owasp.org\n")
    begin
      code = Mzap::CLI.run(["spider", "--urls", config_path, "--apis", "  ,   "], stdout_io, stderr_io)
      code.should eq(1)
      stderr_io.to_s.includes?("Please input --apis flag").should be_true
    ensure
      File.delete(config_path) if File.exists?(config_path)
    end
  end

  it "returns error for unsupported report format" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider", "--urls", "targets.txt", "--report-format", "xml"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("--report-format supports only html or pdf").should be_true
  end

  it "returns error for unknown option" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--unknown"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Unknown option: --unknown").should be_true
  end

  it "accepts dash-prefixed option value with equals syntax" do
    server = TestServer.new
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    begin
      code = Mzap::CLI.run(["stop", "spider", "--apis", server.url, "--apikey=-dash-key"], stdout_io, stderr_io)
      code.should eq(0)

      requests = server.requests
      requests.size.should eq(1)
      requests[0].api_key.should eq("-dash-key")
    ensure
      server.close
    end
  end

  it "returns error when string option value is missing" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider", "--urls", "--apis", "http://localhost:8090"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --urls").should be_true
  end

  it "returns error when string option equals syntax has empty value" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider", "--urls=", "--apis", "http://localhost:8090"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --urls").should be_true
  end

  it "returns error for invalid wait interval integer" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--wait-interval", "abc"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Invalid integer for --wait-interval").should be_true
  end

  it "returns error when wait timeout value is missing" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--wait-timeout"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --wait-timeout").should be_true
  end

  it "returns error when report output is set without report format" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider", "--urls", "targets.txt", "--report-out", "report.html"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("--report-out requires --report-format").should be_true
  end

  it "returns error when wait/report options are used with non-scan commands" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--wait"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("--wait and report options are only available").should be_true
  end
end
