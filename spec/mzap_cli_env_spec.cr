require "./spec_helper"

describe Mzap::CLI do
  it "loads MZAP_APIS from environment variable" do
    server = TestServer.new

    begin
      ENV["MZAP_APIS"] = server.url
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      code = Mzap::CLI.run(["stop", "spider"], stdout_io, stderr_io)
      code.should eq(0)

      requests = server.requests
      requests.size.should eq(1)
    ensure
      ENV.delete("MZAP_APIS")
      server.close
    end
  end

  it "loads MZAP_APIKEY from environment variable" do
    server = TestServer.new

    begin
      ENV["MZAP_APIS"] = server.url
      ENV["MZAP_APIKEY"] = "env-key-123"
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      code = Mzap::CLI.run(["stop", "spider"], stdout_io, stderr_io)
      code.should eq(0)

      requests = server.requests
      requests[0].api_key.should eq("env-key-123")
    ensure
      ENV.delete("MZAP_APIS")
      ENV.delete("MZAP_APIKEY")
      server.close
    end
  end

  it "CLI flags take priority over environment variables" do
    env_server = TestServer.new
    cli_server = TestServer.new

    begin
      ENV["MZAP_APIS"] = env_server.url
      ENV["MZAP_APIKEY"] = "env-key"
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      code = Mzap::CLI.run(
        ["stop", "spider", "--apis", cli_server.url, "--apikey", "cli-key"],
        stdout_io,
        stderr_io
      )
      code.should eq(0)

      env_server.requests.should be_empty
      cli_server.requests.size.should eq(1)
      cli_server.requests[0].api_key.should eq("cli-key")
    ensure
      ENV.delete("MZAP_APIS")
      ENV.delete("MZAP_APIKEY")
      env_server.close
      cli_server.close
    end
  end

  it "loads MZAP_URLS from environment variable" do
    server = TestServer.new

    begin
      with_target_file(["https://env-urls.test"]) do |target_file|
        ENV["MZAP_APIS"] = server.url
        ENV["MZAP_URLS"] = target_file
        stdout_io = IO::Memory.new
        stderr_io = IO::Memory.new
        code = Mzap::CLI.run(["spider"], stdout_io, stderr_io)
        code.should eq(0)

        spider_requests = server.requests.select { |r| r.path == Mzap::Client::SPIDER_API }
        spider_requests.size.should eq(1)
      end
    ensure
      ENV.delete("MZAP_APIS")
      ENV.delete("MZAP_URLS")
      server.close
    end
  end

  it "loads MZAP_WAIT from environment variable" do
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
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      with_target_file(["https://env-wait.test"]) do |target_file|
        ENV["MZAP_APIS"] = server.url
        ENV["MZAP_URLS"] = target_file
        ENV["MZAP_WAIT"] = "true"
        stdout_io = IO::Memory.new
        stderr_io = IO::Memory.new
        code = Mzap::CLI.run(["spider"], stdout_io, stderr_io)
        code.should eq(0)

        paths = server.requests.map(&.path)
        paths.includes?(Mzap::Client::SPIDER_STATUS).should be_true
      end
    ensure
      ENV.delete("MZAP_APIS")
      ENV.delete("MZAP_URLS")
      ENV.delete("MZAP_WAIT")
      server.close
    end
  end

  it "ignores empty environment variables" do
    begin
      ENV["MZAP_APIS"] = ""
      ENV["MZAP_APIKEY"] = ""
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      code = Mzap::CLI.run(["version"], stdout_io, stderr_io)
      code.should eq(0)
    ensure
      ENV.delete("MZAP_APIS")
      ENV.delete("MZAP_APIKEY")
    end
  end
end
