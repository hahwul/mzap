require "./spec_helper"

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

  it "warns and skips scan when target file has no valid entries" do
    server = TestServer.new

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["", "   ", "  # comment"]) do |target_file|
        options = Mzap::Options.new("", target_file)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      server.requests.should be_empty
      stderr_io.to_s.includes?("no targets loaded from file").should be_true
    ensure
      server.close
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
      stderr_io.to_s.includes?("HTTP 500").should be_true
      stdout_io.to_s.includes?("added").should be_false
    ensure
      server.close
    end
  end

  it "reports access endpoint failure details without aborting scan submission" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      if context.request.path == Mzap::Client::ACCESS_API
        context.response.status_code = 500
        context.response.print("access error")
      else
        context.response.status_code = 200
        context.response.print(%({"scan":"2"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://access-error.test"]) do |target_file|
        options = Mzap::Options.new("", target_file)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      stderr_io.to_s.includes?("error (access)").should be_true
      stderr_io.to_s.includes?("HTTP 500").should be_true
      stdout_io.to_s.includes?("added").should be_true
    ensure
      server.close
    end
  end

  it "prints scan summary counts for mixed scan results" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print("ok")
      when Mzap::Client::SPIDER_API
        target = HTTP::Params.parse(context.request.query || "")["url"]?
        if target == "https://bad.test"
          context.response.status_code = 500
          context.response.print("scan error")
        else
          context.response.status_code = 200
          context.response.print(%({"scan":"10"}))
        end
      else
        context.response.status_code = 404
        context.response.print("not found")
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://ok.test", "https://bad.test"]) do |target_file|
        options = Mzap::Options.new("", target_file)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      stdout = stdout_io.to_s
      stderr = stderr_io.to_s
      stdout.includes?("summary targets=2 success=1 scan_errors=1 access_errors=0").should be_true
      stderr.includes?("error (scan)").should be_true
      stderr.includes?("HTTP 500").should be_true
    ensure
      server.close
    end
  end

  it "uses generic scan label for custom scan prefixes" do
    custom_prefix = "/JSON/custom/action/scan/"
    server = TestServer.new

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://custom-prefix.test"]) do |target_file|
        options = Mzap::Options.new("", target_file)
        Mzap::Client.run(target_file, server.url, custom_prefix, options, reporter)
      end

      paths = server.requests.map(&.path)
      paths.includes?(Mzap::Client::ACCESS_API).should be_true
      paths.includes?(custom_prefix).should be_true
      stdout = stdout_io.to_s
      stdout.includes?("[scan]").should be_true
      stderr_io.to_s.empty?.should be_true
    ensure
      server.close
    end
  end

  it "removes duplicate targets and warns about removed count" do
    server = TestServer.new

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://dup.test", "https://dup.test", "https://unique.test"]) do |target_file|
        options = Mzap::Options.new("", target_file)
        Mzap.spider(target_file, server.url, options, reporter)
      end

      requests = server.requests
      scan_requests = requests.select { |r| r.path == Mzap::Client::SPIDER_API }
      scan_requests.size.should eq(2)
      targets = scan_requests.map { |r| HTTP::Params.parse(r.query || "")["url"] }
      targets.should eq(["https://dup.test", "https://unique.test"])
      stderr_io.to_s.includes?("removed 1 duplicate target(s)").should be_true
    ensure
      server.close
    end
  end

  it "warns and returns when target file does not exist" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    reporter = Mzap::Reporter.new(stdout_io, stderr_io)

    Mzap::Client.run("/tmp/definitely-nonexistent-mzap-file.txt", "http://127.0.0.1:1", Mzap::Client::SPIDER_API, Mzap::Options.new("", ""), reporter)

    stderr_io.to_s.includes?("target file not found").should be_true
  end

  it "strips trailing slash from API host to avoid double slashes" do
    server = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://trailing.test"]) do |target_file|
        options = Mzap::Options.new("", target_file)
        Mzap.spider(target_file, "#{server.url}/", options, reporter)
      end

      requests = server.requests
      requests.size.should eq(2)
      requests[0].path.should eq(Mzap::Client::ACCESS_API)
      requests[1].path.should eq(Mzap::Client::SPIDER_API)
    ensure
      server.close
    end
  end

  it "shows transport error for empty error message" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    reporter = Mzap::Reporter.new(stdout_io, stderr_io)

    with_target_file(["https://transport-empty.test"]) do |target_file|
      options = Mzap::Options.new("", target_file)
      Mzap.spider(target_file, "http://127.0.0.1:1", options, reporter)
    end

    stderr = stderr_io.to_s
    stderr.includes?("error (access)").should be_true
    stderr.includes?("error (scan)").should be_true
  end

  it "counts transport failures for access and scan API calls" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    reporter = Mzap::Reporter.new(stdout_io, stderr_io)

    with_target_file(["https://transport-fail.test"]) do |target_file|
      options = Mzap::Options.new("", target_file)
      Mzap.spider(target_file, "http://127.0.0.1:1", options, reporter)
    end

    stderr = stderr_io.to_s
    stdout = stdout_io.to_s
    stderr.includes?("error (access)").should be_true
    stderr.includes?("error (scan)").should be_true
    stdout.includes?("summary targets=1 success=0 scan_errors=1 access_errors=1").should be_true
  end
end
