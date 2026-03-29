require "./spec_helper"

describe Mzap do
  it "passes scan policy name to active scan API" do
    server = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://policy.test"]) do |target_file|
        options = Mzap::Options.new(policy: "API-Minimal-Scan")
        Mzap.active_scan(target_file, apis: server.url, options: options, reporter: reporter)
      end

      ascan_request = server.requests.find { |r| r.path == Mzap::Client::ASCAN_API }
      ascan_request.should_not be_nil
      params = HTTP::Params.parse(ascan_request.not_nil!.query || "")
      params["scanPolicyName"].should eq("API-Minimal-Scan")
    ensure
      server.close
    end
  end

  it "omits scanPolicyName when policy is empty" do
    server = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://no-policy.test"]) do |target_file|
        options = Mzap::Options.new
        Mzap.active_scan(target_file, apis: server.url, options: options, reporter: reporter)
      end

      ascan_request = server.requests.find { |r| r.path == Mzap::Client::ASCAN_API }
      ascan_request.should_not be_nil
      params = HTTP::Params.parse(ascan_request.not_nil!.query || "")
      params.has_key?("scanPolicyName").should be_false
    ensure
      server.close
    end
  end

  it "does not pass policy to spider scan" do
    server = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://spider-policy.test"]) do |target_file|
        options = Mzap::Options.new(policy: "some-policy")
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      spider_request = server.requests.find { |r| r.path == Mzap::Client::SPIDER_API }
      spider_request.should_not be_nil
      params = HTTP::Params.parse(spider_request.not_nil!.query || "")
      params.has_key?("scanPolicyName").should be_false
    ensure
      server.close
    end
  end

  it "accepts --policy via CLI for ascan" do
    server = TestServer.new

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      with_target_file(["https://cli-policy.test"]) do |target_file|
        code = Mzap::CLI.run(
          ["ascan", "--urls", target_file, "--apis", server.url, "--policy", "My-Policy"],
          stdout_io,
          stderr_io
        )
        code.should eq(0)
      end

      ascan_request = server.requests.find { |r| r.path == Mzap::Client::ASCAN_API }
      ascan_request.should_not be_nil
      params = HTTP::Params.parse(ascan_request.not_nil!.query || "")
      params["scanPolicyName"].should eq("My-Policy")
    ensure
      server.close
    end
  end
end
