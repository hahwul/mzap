require "./spec_helper"

describe Mzap do
  it "retries failed scan requests" do
    scan_calls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        scan_calls += 1
        if scan_calls <= 2
          context.response.status_code = 500
          context.response.print(%({"error":"busy"}))
        else
          context.response.status_code = 200
          context.response.print(%({"scan":"1"}))
        end
      else
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://retry.test"]) do |target_file|
        options = Mzap::Options.new(retry_count: 3, retry_delay_seconds: 0)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      scan_calls.should eq(3)
      stderr = stderr_io.to_s
      stderr.includes?("retry 1/3").should be_true
      stderr.includes?("retry 2/3").should be_true
      stdout_io.to_s.includes?("success=1").should be_true
    ensure
      server.close
    end
  end

  it "fails after exhausting all retries" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 500
        context.response.print(%({"error":"always fail"}))
      else
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://retry-exhaust.test"]) do |target_file|
        options = Mzap::Options.new(retry_count: 2, retry_delay_seconds: 0)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      stderr = stderr_io.to_s
      stderr.includes?("retry 1/2").should be_true
      stderr.includes?("retry 2/2").should be_true
      stderr.includes?("error (scan)").should be_true
      stdout_io.to_s.includes?("success=0").should be_true
    ensure
      server.close
    end
  end

  it "does not retry when retry count is 0" do
    scan_calls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        scan_calls += 1
        context.response.status_code = 500
        context.response.print(%({"error":"fail"}))
      else
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(IO::Memory.new, stderr_io)
      with_target_file(["https://no-retry.test"]) do |target_file|
        options = Mzap::Options.new(retry_count: 0)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      scan_calls.should eq(1)
      stderr_io.to_s.includes?("retry 1/").should be_false
    ensure
      server.close
    end
  end

  it "retries access URL failures" do
    access_calls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        access_calls += 1
        if access_calls <= 1
          context.response.status_code = 500
          context.response.print(%({"error":"busy"}))
        else
          context.response.status_code = 200
          context.response.print(%({"ok":"true"}))
        end
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"1"}))
      else
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://retry-access.test"]) do |target_file|
        options = Mzap::Options.new(retry_count: 2, retry_delay_seconds: 0)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      access_calls.should eq(2)
      stderr = stderr_io.to_s
      stderr.includes?("access failed").should be_true
      stderr.includes?("retry 1/2").should be_true
      stdout_io.to_s.includes?("access_errors=0").should be_true
    ensure
      server.close
    end
  end

  it "accepts --retry and --retry-delay via CLI" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    code = Mzap::CLI.run(["spider", "--urls", "targets.txt", "--retry", "3", "--retry-delay", "1"], stdout_io, stderr_io)
    stderr_io.to_s.includes?("--retry must be").should be_false
  end

  it "rejects negative --retry value" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    code = Mzap::CLI.run(["spider", "--urls", "targets.txt", "--retry", "-1"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("--retry must be 0 or greater").should be_true
  end
end
