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
      rescue IO::Error
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
      stdout_io.to_s.includes?("added").should be_false
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
      stdout_io.to_s.includes?("stopped").should be_false
    ensure
      server.close
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
end
