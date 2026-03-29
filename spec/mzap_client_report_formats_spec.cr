require "./spec_helper"

ALERTS_API_PATH = "/JSON/alert/view/alerts/"

describe Mzap do
  it "requests json report using traditional-json template" do
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
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    report_path = "#{File.tempname("mzap-json-report")}.json"
    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://json.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, report_format: "json", report_out: report_path)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      report_request = server.requests.find { |r| r.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should_not be_nil
      params = HTTP::Params.parse(report_request.not_nil!.query || "")
      params["template"].should eq("traditional-json")
    ensure
      File.delete(report_path) if File.exists?(report_path)
      server.close
    end
  end

  it "requests markdown report using traditional-md template" do
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
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    report_path = "#{File.tempname("mzap-md-report")}.md"
    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://md.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, report_format: "md", report_out: report_path)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      report_request = server.requests.find { |r| r.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should_not be_nil
      params = HTTP::Params.parse(report_request.not_nil!.query || "")
      params["template"].should eq("traditional-md")
    ensure
      File.delete(report_path) if File.exists?(report_path)
      server.close
    end
  end

  it "generates sarif report from alerts without using ZAP reports API" do
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
      when ALERTS_API_PATH
        context.response.status_code = 200
        context.response.print(%({"alerts":[{"pluginId":"10021","alert":"X-Content-Type-Options Header Missing","name":"X-Content-Type-Options Header Missing","risk":"Low","confidence":"Medium","url":"https://sarif.test","description":"Missing header","solution":"Add header"}]}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    report_path = "#{File.tempname("mzap-sarif-report")}.sarif"
    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://sarif.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, report_format: "sarif", report_out: report_path)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      # SARIF should not use ZAP Reports API
      report_request = server.requests.find { |r| r.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should be_nil

      # Should have fetched alerts
      alerts_request = server.requests.find { |r| r.path == ALERTS_API_PATH }
      alerts_request.should_not be_nil

      # Verify SARIF output
      File.exists?(report_path).should be_true
      sarif_content = File.read(report_path)
      sarif_json = JSON.parse(sarif_content)
      sarif_json["version"].as_s.should eq("2.1.0")
      runs = sarif_json["runs"].as_a
      runs.size.should eq(1)
      results = runs[0]["results"].as_a
      results.size.should eq(1)
      results[0]["ruleId"].as_s.should eq("10021")
    ensure
      File.delete(report_path) if File.exists?(report_path)
      server.close
    end
  end

  it "falls back to alerts API for json format when reports API fails" do
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
        context.response.status_code = 500
        context.response.print(%({"error":"reports add-on not available"}))
      when ALERTS_API_PATH
        context.response.status_code = 200
        context.response.print(%({"alerts":[{"alert":"XSS","risk":"High"}]}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    report_path = "#{File.tempname("mzap-json-fallback")}.json"
    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://json-fallback.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, report_format: "json", report_out: report_path)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      File.exists?(report_path).should be_true
      content = JSON.parse(File.read(report_path))
      content["alerts"].as_a.size.should eq(1)
    ensure
      File.delete(report_path) if File.exists?(report_path)
      server.close
    end
  end

  it "falls back to markdown generated from alerts when reports API fails" do
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
        context.response.status_code = 500
        context.response.print(%({"error":"reports add-on not available"}))
      when ALERTS_API_PATH
        context.response.status_code = 200
        context.response.print(%({"alerts":[{"alert":"SQL Injection","name":"SQL Injection","risk":"High","confidence":"Medium","url":"https://md-fallback.test","description":"SQL injection found","solution":"Use parameterized queries"}]}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    report_path = "#{File.tempname("mzap-md-fallback")}.md"
    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://md-fallback.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, report_format: "md", report_out: report_path)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      File.exists?(report_path).should be_true
      content = File.read(report_path)
      content.includes?("# ZAP Scan Report").should be_true
      content.includes?("SQL Injection").should be_true
      content.includes?("**Risk**: High").should be_true
    ensure
      File.delete(report_path) if File.exists?(report_path)
      server.close
    end
  end

  it "accepts json, md, and sarif via CLI --report-format" do
    {"json", "md", "sarif"}.each do |format|
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      code = Mzap::CLI.run(["spider", "--urls", "targets.txt", "--report-format", format], stdout_io, stderr_io)
      stderr_io.to_s.includes?("--report-format supports only").should be_false
    end
  end
end
