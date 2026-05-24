require "./spec_helper"

class Zap::Client
  class_property init_count : Int32 = 0
  class_property? should_raise_after : Int32? = nil

  def self.new(base_url : String = "http://localhost:8080", api_key : String = "", connect_timeout : Time::Span = 30.seconds, read_timeout : Time::Span = 300.seconds)
    @@init_count += 1
    if limit = @@should_raise_after
      if @@init_count > limit
        raise Exception.new("Mocked Zap::Client init exception")
      end
    end
    client = allocate
    client.initialize(base_url, api_key, connect_timeout, read_timeout)
    client
  end
end

describe Mzap do
  it "dispatches scans concurrently with --concurrency flag" do
    server = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://a.test", "https://b.test", "https://c.test"]) do |target_file|
        options = Mzap::Options.new(concurrency: 3)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      requests = server.requests
      spider_requests = requests.select { |r| r.path == Mzap::Client::SPIDER_API }
      spider_requests.size.should eq(3)
      targets = spider_requests.map { |r| HTTP::Params.parse(r.query || "")["url"] }.sort
      targets.should eq(["https://a.test", "https://b.test", "https://c.test"])
    ensure
      server.close
    end
  end

  it "limits concurrent dispatches to the specified concurrency value" do
    max_concurrent = Atomic(Int32).new(0)
    current_concurrent = Atomic(Int32).new(0)

    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::SPIDER_API
        current = current_concurrent.add(1) + 1
        loop do
          old_max = max_concurrent.get
          break if current <= old_max
          break if max_concurrent.compare_and_set(old_max, current) == {old_max, true}
        end
        sleep 10.milliseconds
        current_concurrent.sub(1)
        context.response.status_code = 200
        context.response.print(%({"scan":"1"}))
      else
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://c1.test", "https://c2.test", "https://c3.test", "https://c4.test"]) do |target_file|
        options = Mzap::Options.new(concurrency: 2)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      max_concurrent.get.should be <= 2
    ensure
      server.close
    end
  end

  it "defaults to sequential execution with concurrency 1" do
    server = TestServer.new

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://seq1.test", "https://seq2.test"]) do |target_file|
        options = Mzap::Options.new(concurrency: 1)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      spider_requests = server.requests.select { |r| r.path == Mzap::Client::SPIDER_API }
      spider_requests.size.should eq(2)
      stdout_io.to_s.includes?("success=2").should be_true
    ensure
      server.close
    end
  end

  it "handles concurrent scan errors without losing count" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        target = HTTP::Params.parse(context.request.query || "")["url"]?
        if target == "https://fail.test"
          context.response.status_code = 500
          context.response.print(%({"error":"scan error"}))
        else
          context.response.status_code = 200
          context.response.print(%({"scan":"1"}))
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
      with_target_file(["https://ok.test", "https://fail.test"]) do |target_file|
        options = Mzap::Options.new(concurrency: 2)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      stdout = stdout_io.to_s
      stdout.includes?("success=1").should be_true
      stdout.includes?("scan_errors=1").should be_true
    ensure
      server.close
    end
  end

  it "rejects --concurrency 0 via CLI" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    code = Mzap::CLI.run(["spider", "--urls", "targets.txt", "--concurrency", "0"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("--concurrency must be greater than 0").should be_true
  end

  it "accepts --concurrency via CLI" do
    server = TestServer.new

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      with_target_file(["https://cli-conc.test"]) do |target_file|
        code = Mzap::CLI.run(
          ["spider", "--urls", target_file, "--apis", server.url, "--concurrency", "2"],
          stdout_io,
          stderr_io
        )
        code.should eq(0)
      end

      spider_requests = server.requests.select { |r| r.path == Mzap::Client::SPIDER_API }
      spider_requests.size.should eq(1)
    ensure
      server.close
    end
  end

  it "works with concurrent dispatch and wait mode" do
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
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://wait1.test", "https://wait2.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, concurrency: 2)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      stdout = stdout_io.to_s
      stdout.includes?("success=2").should be_true
      stdout.includes?("scan_completed=2/2").should be_true
    ensure
      server.close
    end
  end

  it "does not deadlock if client initialization fails in spawned concurrent fibers" do
    server = TestServer.new
    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://conc-fail1.test", "https://conc-fail2.test"]) do |target_file|
        options = Mzap::Options.new(concurrency: 2)
        Zap::Client.init_count = 0
        Zap::Client.should_raise_after = 1
        begin
          Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
        ensure
          Zap::Client.should_raise_after = nil
        end
      end

      stdout = stdout_io.to_s
      stderr = stderr_io.to_s
      stdout.includes?("scan_errors=2").should be_true
      stderr.includes?("fiber dispatch failed").should be_true
    ensure
      server.close
    end
  end
end
