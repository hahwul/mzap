require "./spec_helper"

describe Mzap do
  it "imports an openapi spec from a url via the importUrl endpoint" do
    server = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://api.example.com/openapi.json"]) do |spec_file|
        options = Mzap::Options.new(api_key: "imp-key")
        Mzap.import_api(spec_file, format: "openapi", target_url: "https://api.example.com", apis: server.url, options: options, reporter: reporter)
      end

      requests = server.requests
      requests.size.should eq(1)
      requests[0].path.should eq(Mzap::Client::OPENAPI_IMPORT_URL_API)
      params = HTTP::Params.parse(requests[0].query || "")
      params["url"].should eq("https://api.example.com/openapi.json")
      params["hostOverride"].should eq("https://api.example.com")
      requests[0].api_key.should eq("imp-key")
    ensure
      server.close
    end
  end

  it "imports an openapi spec from a local file via the importFile endpoint" do
    server = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["/specs/api.yaml"]) do |spec_file|
        options = Mzap::Options.new
        Mzap.import_api(spec_file, format: "openapi", target_url: "https://api.example.com", apis: server.url, options: options, reporter: reporter)
      end

      requests = server.requests
      requests.size.should eq(1)
      requests[0].path.should eq(Mzap::Client::OPENAPI_IMPORT_FILE_API)
      params = HTTP::Params.parse(requests[0].query || "")
      params["file"].should eq("/specs/api.yaml")
      params["target"].should eq("https://api.example.com")
    ensure
      server.close
    end
  end

  it "routes each format to its import endpoint" do
    cases = {
      "soap"    => {"https://svc.example.com?wsdl", Mzap::Client::SOAP_IMPORT_URL_API},
      "graphql" => {"https://api.example.com/graphql", Mzap::Client::GRAPHQL_IMPORT_URL_API},
      "postman" => {"https://api.example.com/collection.json", Mzap::Client::POSTMAN_IMPORT_URL_API},
    }

    cases.each do |format, (spec, expected_path)|
      server = TestServer.new
      begin
        reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
        with_target_file([spec]) do |spec_file|
          options = Mzap::Options.new
          Mzap.import_api(spec_file, format: format, apis: server.url, options: options, reporter: reporter)
        end

        requests = server.requests
        requests.size.should eq(1)
        requests[0].path.should eq(expected_path)
        HTTP::Params.parse(requests[0].query || "")["url"].should eq(spec)
      ensure
        server.close
      end
    end
  end

  it "distributes specs across hosts round-robin" do
    server1 = TestServer.new
    server2 = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://a.example/openapi.json", "https://b.example/openapi.json", "https://c.example/openapi.json"]) do |spec_file|
        options = Mzap::Options.new
        Mzap.import_api(spec_file, format: "openapi", apis: "#{server1.url},#{server2.url}", options: options, reporter: reporter)
      end

      server1.requests.size.should eq(2)
      server2.requests.size.should eq(1)
    ensure
      server1.close
      server2.close
    end
  end

  it "waits for passive scan to settle after import when wait is enabled" do
    pscan_calls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 200
      case context.request.path
      when Mzap::Client::PSCAN_RECORDS_TO_SCAN
        pscan_calls += 1
        context.response.print(pscan_calls >= 2 ? %({"recordsToScan":"0"}) : %({"recordsToScan":"3"}))
      else
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, IO::Memory.new)
      with_target_file(["https://api.example.com/openapi.json"]) do |spec_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5)
        Mzap.import_api(spec_file, format: "openapi", apis: server.url, options: options, reporter: reporter)
      end

      pscan_calls.should eq(2)
      stdout_io.to_s.includes?("completed=1/1").should be_true
    ensure
      server.close
    end
  end

  it "reports a summary and skips when the spec list is empty" do
    server = TestServer.new

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["", "  # comment only"]) do |spec_file|
        options = Mzap::Options.new
        Mzap.import_api(spec_file, format: "openapi", apis: server.url, options: options, reporter: reporter)
      end

      server.requests.should be_empty
      stderr_io.to_s.includes?("no specs loaded from file").should be_true
    ensure
      server.close
    end
  end

  it "runs import via CLI and requires --format" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    with_target_file(["https://api.example.com/openapi.json"]) do |spec_file|
      code = Mzap::CLI.run(["import", "--urls", spec_file], stdout_io, stderr_io)
      code.should eq(1)
      stderr_io.to_s.includes?("--format is required").should be_true
    end
  end

  it "rejects an unknown import format via CLI" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    with_target_file(["https://api.example.com/openapi.json"]) do |spec_file|
      code = Mzap::CLI.run(["import", "--format", "wsdlx", "--urls", spec_file], stdout_io, stderr_io)
      code.should eq(1)
      stderr_io.to_s.includes?("--format supports only").should be_true
    end
  end

  it "runs a successful import via CLI" do
    server = TestServer.new

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      with_target_file(["https://api.example.com/openapi.json"]) do |spec_file|
        code = Mzap::CLI.run(["import", "--format", "openapi", "--urls", spec_file, "--apis", server.url], stdout_io, stderr_io)
        code.should eq(0)
      end

      paths = server.requests.map(&.path)
      paths.includes?(Mzap::Client::OPENAPI_IMPORT_URL_API).should be_true
    ensure
      server.close
    end
  end
end
