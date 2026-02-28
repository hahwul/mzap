require "./spec_helper"

describe Mzap do
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

  it "reports transport failures when stop endpoints are unreachable" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    reporter = Mzap::Reporter.new(stdout_io, stderr_io)
    options = Mzap::Options.new("", "")

    Mzap.stop_spider("http://127.0.0.1:1,http://127.0.0.1:2", options, reporter)

    stderr = stderr_io.to_s
    stdout = stdout_io.to_s
    stderr.includes?("error (stop)").should be_true
    stdout.includes?("summary success=0 failed=2").should be_true
  end

  it "handles successful empty-body responses for stop endpoints" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 200
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      options = Mzap::Options.new("", "")
      Mzap.stop_spider(server.url, options, reporter)

      stdout_io.to_s.includes?("stopped").should be_true
      stderr_io.to_s.should eq("")
    ensure
      server.close
    end
  end
end
