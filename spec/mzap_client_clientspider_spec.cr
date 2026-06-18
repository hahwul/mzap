require "./spec_helper"

describe Mzap do
  it "runs client spider scan endpoint after accessing the url" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 200
      if context.request.path == Mzap::Client::CLIENT_SPIDER_API
        context.response.print(%({"scan":"3"}))
      else
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://spa.test"]) do |target_file|
        options = Mzap::Options.new
        Mzap.client_spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      requests = server.requests
      requests.size.should eq(2)
      requests[0].path.should eq(Mzap::Client::ACCESS_API)
      requests[1].path.should eq(Mzap::Client::CLIENT_SPIDER_API)
      HTTP::Params.parse(requests[1].query || "")["url"].should eq("https://spa.test")
    ensure
      server.close
    end
  end

  it "waits for client spider completion using percentage status" do
    polls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 200
      case context.request.path
      when Mzap::Client::CLIENT_SPIDER_API
        context.response.print(%({"scan":"5"}))
      when Mzap::Client::CLIENT_SPIDER_STAT
        polls += 1
        context.response.print(polls >= 2 ? %({"status":"100"}) : %({"status":"40"}))
      else
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, IO::Memory.new)
      with_target_file(["https://spa.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 1)
        Mzap.client_spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      status_request = server.requests.find { |r| r.path == Mzap::Client::CLIENT_SPIDER_STAT }
      status_request.should_not be_nil
      HTTP::Params.parse(status_request.not_nil!.query || "")["scanId"].should eq("5")
      stdout_io.to_s.includes?("complete").should be_true
    ensure
      server.close
    end
  end

  it "sends client spider stop request" do
    server = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      options = Mzap::Options.new(api_key: "stop-key")
      Mzap.stop_client_spider(server.url, options: options, reporter: reporter)

      requests = server.requests
      requests.size.should eq(1)
      requests[0].path.should eq(Mzap::Client::CLIENT_SPIDER_STOP)
      requests[0].api_key.should eq("stop-key")
    ensure
      server.close
    end
  end
end
