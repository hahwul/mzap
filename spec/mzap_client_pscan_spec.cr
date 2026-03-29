require "./spec_helper"

PSCAN_RECORDS_PATH = Mzap::Client::PSCAN_RECORDS_TO_SCAN

describe Mzap do
  it "waits for passive scan completion when records to scan reaches 0" do
    pscan_calls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when PSCAN_RECORDS_PATH
        pscan_calls += 1
        context.response.status_code = 200
        if pscan_calls == 1
          context.response.print(%({"recordsToScan":"5"}))
        else
          context.response.print(%({"recordsToScan":"0"}))
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
      options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5)
      Mzap.passive_scan(server.url, options: options, reporter: reporter)

      pscan_calls.should eq(2)
      stdout = stdout_io.to_s
      stdout.includes?("completed=1/1").should be_true
      stdout.includes?("timed_out=false").should be_true
    ensure
      server.close
    end
  end

  it "times out when passive scan records never reach 0" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when PSCAN_RECORDS_PATH
        context.response.status_code = 200
        context.response.print(%({"recordsToScan":"10"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 1, wait_timeout_seconds: 1)
      Mzap.passive_scan(server.url, options: options, reporter: reporter)

      stderr = stderr_io.to_s
      stdout = stdout_io.to_s
      stderr.includes?("timeout").should be_true
      stdout.includes?("timed_out=true").should be_true
    ensure
      server.close
    end
  end

  it "handles HTTP errors when polling passive scan status" do
    pscan_calls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when PSCAN_RECORDS_PATH
        pscan_calls += 1
        if pscan_calls <= 2
          context.response.status_code = 500
          context.response.print(%({"error":"internal error"}))
        else
          context.response.status_code = 200
          context.response.print(%({"recordsToScan":"0"}))
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
      options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5)
      Mzap.passive_scan(server.url, options: options, reporter: reporter)

      stderr = stderr_io.to_s
      stdout = stdout_io.to_s
      stderr.includes?("status check failed (HTTP 500)").should be_true
      stderr.scan(/status check failed \(HTTP 500\)/).size.should eq(1)
      stdout.includes?("completed=1/1").should be_true
    ensure
      server.close
    end
  end

  it "handles missing recordsToScan value in response" do
    pscan_calls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when PSCAN_RECORDS_PATH
        pscan_calls += 1
        context.response.status_code = 200
        if pscan_calls == 1
          context.response.print(%({}))
        else
          context.response.print(%({"recordsToScan":"0"}))
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
      options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5)
      Mzap.passive_scan(server.url, options: options, reporter: reporter)

      stderr = stderr_io.to_s
      stderr.includes?("missing recordsToScan value").should be_true
      stdout_io.to_s.includes?("completed=1/1").should be_true
    ensure
      server.close
    end
  end

  it "polls multiple ZAP hosts independently" do
    server1 = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when PSCAN_RECORDS_PATH
        context.response.status_code = 200
        context.response.print(%({"recordsToScan":"0"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    server2 = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when PSCAN_RECORDS_PATH
        context.response.status_code = 200
        context.response.print(%({"recordsToScan":"0"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5)
      Mzap.passive_scan("#{server1.url},#{server2.url}", options: options, reporter: reporter)

      stdout = stdout_io.to_s
      stdout.includes?("completed=2/2").should be_true
      stdout.includes?("timed_out=false").should be_true
    ensure
      server1.close
      server2.close
    end
  end

  it "runs pscan command via CLI" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when PSCAN_RECORDS_PATH
        context.response.status_code = 200
        context.response.print(%({"recordsToScan":"0"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      code = Mzap::CLI.run(["pscan", "--apis", server.url], stdout_io, stderr_io)
      code.should eq(0)

      paths = server.requests.map(&.path)
      paths.includes?(PSCAN_RECORDS_PATH).should be_true
      stdout_io.to_s.includes?("completed=1/1").should be_true
    ensure
      server.close
    end
  end

  it "shows pscan help text" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    code = Mzap::CLI.run(["help", "pscan"], stdout_io, stderr_io)
    code.should eq(0)
    stdout_io.to_s.includes?("Wait for Passive Scan completion").should be_true
  end

  it "runs pscan with numeric recordsToScan value" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when PSCAN_RECORDS_PATH
        context.response.status_code = 200
        context.response.print(%({"recordsToScan":0}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5)
      Mzap.passive_scan(server.url, options: options, reporter: reporter)

      stdout_io.to_s.includes?("completed=1/1").should be_true
    ensure
      server.close
    end
  end
end
