require "./spec_helper"

describe "Mzap Security" do
  it "prevents path traversal in filtered report generation" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 200
      context.response.print(%({"result":"ok"}))
    end)

    traversal_path = "../../tmp/mzap-traversal-test.html"

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://traversal.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, false, 0, 5, "html", traversal_path)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      # Should NOT have made any report requests because path traversal was blocked
      report_request = server.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should be_nil

      # Should have logged an error message
      stderr_io.to_s.includes?("Path traversal detected").should be_true
    ensure
      server.close
    end
  end

  it "prevents path traversal in core report generation" do
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
        context.response.status_code = 404 # Force fallback
      when Mzap::Client::HTML_REPORT_API
        context.response.status_code = 200
        context.response.print("<html>vulnerable</html>")
      end
    end)

    traversal_path = "../../tmp/mzap-core-traversal-test.html"
    full_traversal_path = File.expand_path(traversal_path)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://traversal-core.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, true, 0, 5, "html", traversal_path)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      # File should NOT exist
      File.exists?(full_traversal_path).should be_false

      # Should have logged error messages for both attempts
      stderr_io.to_s.scan(/Path traversal detected/).size.should eq(2)
    ensure
      File.delete(full_traversal_path) if File.exists?(full_traversal_path)
      server.close
    end
  end

  it "blocks absolute paths outside of CWD" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 200
      context.response.print(%({"result":"ok"}))
    end)

    # Use an absolute path that is definitely outside our current project
    traversal_path = "/tmp/mzap-absolute-traversal-test.html"

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://traversal-abs.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, false, 0, 5, "html", traversal_path)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      report_request = server.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should be_nil
      stderr_io.to_s.includes?("Path traversal detected").should be_true
    ensure
      server.close
    end
  end

  it "allows paths within CWD" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 200
      context.response.print(%({"result":"ok"}))
    end)

    report_dir = "test-reports"
    report_path = "#{report_dir}/safe-report.html"

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://safe.test"]) do |target_file|
        options = Mzap::Options.new("", target_file, false, 0, 5, "html", report_path)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      report_request = server.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should_not be_nil
      stderr_io.to_s.includes?("Path traversal detected").should be_false
    ensure
      FileUtils.rm_rf(report_dir) if Dir.exists?(report_dir)
      server.close
    end
  end
end
