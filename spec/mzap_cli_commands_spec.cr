require "./spec_helper"

describe Mzap::CLI do
  it "prints missing urls message for spider command" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider"], stdout_io, stderr_io)
    code.should eq(1)
    stdout_io.to_s.includes?("Please input --urls flag").should be_true
  end

  it "prints missing urls message for ajaxspider command" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["ajaxspider"], stdout_io, stderr_io)
    code.should eq(1)
    stdout_io.to_s.includes?("Please input --urls flag").should be_true
  end

  it "prints missing urls message for ascan command" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["ascan"], stdout_io, stderr_io)
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

  it "accepts explicit non-toml config path without loading scan options from it" do
    config_path = "#{File.tempname("mzap-config")}.yaml"
    File.write(
      config_path,
      <<-YAML
      apis: "http://example.invalid:8090"
      urls: "/tmp/targets.txt"
      wait: true
      report_format: "html"
      YAML
    )

    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    begin
      code = Mzap::CLI.run(["spider", "--config", config_path], stdout_io, stderr_io)
      code.should eq(1)
      stdout = stdout_io.to_s
      stdout.includes?("Using config file: #{config_path}").should be_true
      stdout.includes?("Please input --urls flag").should be_true
      stderr_io.to_s.includes?("Invalid TOML").should be_false
    ensure
      File.delete(config_path) if File.exists?(config_path)
    end
  end

  it "loads API host and key from default TOML config" do
    server = TestServer.new

    begin
      with_temp_home do |temp_home|
        config_path = File.join(temp_home, ".config", "mzap", "config.toml")
        Dir.mkdir_p(File.dirname(config_path))
        File.write(
          config_path,
          <<-TOML
          [mzap]
          apis = "#{server.url}"
          apikey = "cfg-key"
          TOML
        )

        stdout_io = IO::Memory.new
        stderr_io = IO::Memory.new
        code = Mzap::CLI.run(["stop", "spider"], stdout_io, stderr_io)
        code.should eq(0)

        requests = server.requests
        requests.size.should eq(1)
        requests[0].api_key.should eq("cfg-key")
        stdout_io.to_s.includes?("Using config file: #{config_path}").should be_true
        stderr_io.to_s.includes?("error (stop)").should be_false
      end
    ensure
      server.close
    end
  end

  it "prefers CLI flags over TOML config values" do
    config_server = TestServer.new
    cli_server = TestServer.new

    begin
      with_temp_home do |temp_home|
        config_path = File.join(temp_home, ".config", "mzap", "config.toml")
        Dir.mkdir_p(File.dirname(config_path))
        File.write(
          config_path,
          <<-TOML
          [mzap]
          apis = "#{config_server.url}"
          apikey = "cfg-key"
          TOML
        )

        stdout_io = IO::Memory.new
        stderr_io = IO::Memory.new
        code = Mzap::CLI.run(
          ["stop", "spider", "--apis", cli_server.url, "--apikey", "cli-key"],
          stdout_io,
          stderr_io
        )
        code.should eq(0)

        config_server.requests.should be_empty
        cli_requests = cli_server.requests
        cli_requests.size.should eq(1)
        cli_requests[0].api_key.should eq("cli-key")
        stderr_io.to_s.includes?("error (stop)").should be_false
      end
    ensure
      config_server.close
      cli_server.close
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

  it "runs stop ascan via CLI for active scan endpoint" do
    server = TestServer.new
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    begin
      code = Mzap::CLI.run(["stop", "ascan", "--apis", server.url], stdout_io, stderr_io)
      code.should eq(0)

      requests = server.requests
      requests.size.should eq(1)
      requests[0].path.should eq(stop_path(Mzap::Client::ASCAN_STOP))
    ensure
      server.close
    end
  end

  it "runs stop ajaxspider via CLI for ajax stop endpoint" do
    server = TestServer.new
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    begin
      code = Mzap::CLI.run(["stop", "ajaxspider", "--apis", server.url], stdout_io, stderr_io)
      code.should eq(0)

      requests = server.requests
      requests.size.should eq(1)
      requests[0].path.should eq(stop_path(Mzap::Client::AJAX_SPIDER_STOP))
    ensure
      server.close
    end
  end

  it "accepts uppercase report format values for scan commands" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"15"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      with_target_file(["https://upper-format.test"]) do |target_file|
        code = Mzap::CLI.run(
          ["spider", "--urls", target_file, "--apis", server.url, "--report-format", "HTML"],
          stdout_io,
          stderr_io
        )
        code.should eq(0)
      end

      report_request = server.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should_not be_nil
      params = HTTP::Params.parse(report_request.not_nil!.query || "")
      params["template"].should eq("traditional-html")
    ensure
      server.close
    end
  end

  it "skips config notice when explicit config path does not exist" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    missing_path = File.join(File.tempname("mzap-missing"), "config.toml")

    code = Mzap::CLI.run(["version", "--config", missing_path], stdout_io, stderr_io)
    code.should eq(0)
    stdout_io.to_s.includes?("Using config file:").should be_false
  end

  it "applies wait and report settings from config for scan commands" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"55"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      with_temp_home do |temp_home|
        with_target_file(["https://config-scan-settings.test"]) do |target_file|
          config_path = File.join(temp_home, ".config", "mzap", "config.toml")
          Dir.mkdir_p(File.dirname(config_path))
          File.write(
            config_path,
            <<-TOML
            [mzap]
            apis = "#{server.url}"
            urls = "#{target_file}"
            wait = true
            wait_interval = 1
            wait_timeout = 5
            report_format = "html"
            TOML
          )

          stdout_io = IO::Memory.new
          stderr_io = IO::Memory.new
          code = Mzap::CLI.run(["spider"], stdout_io, stderr_io)
          code.should eq(0)
          stderr_io.to_s.includes?("error").should be_false
        end
      end

      paths = server.requests.map(&.path)
      paths.includes?(Mzap::Client::SPIDER_STATUS).should be_true
      paths.includes?(Mzap::Client::REPORT_GENERATE_API).should be_true
    ensure
      server.close
    end
  end

  it "prefers CLI scan flags over conflicting config wait/report settings" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"56"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    cli_report = "#{File.tempname("mzap-cli-overrides-config")}.html"
    begin
      with_temp_home do |temp_home|
        with_target_file(["https://config-override-scan.test"]) do |target_file|
          config_path = File.join(temp_home, ".config", "mzap", "config.toml")
          Dir.mkdir_p(File.dirname(config_path))
          File.write(
            config_path,
            <<-TOML
            [mzap]
            apis = "#{server.url}"
            urls = "#{target_file}"
            wait_interval = 0
            wait_timeout = -1
            report_format = "xml"
            report_out = "from-config.xml"
            TOML
          )

          stdout_io = IO::Memory.new
          stderr_io = IO::Memory.new
          code = Mzap::CLI.run(
            [
              "spider",
              "--wait-interval",
              "1",
              "--wait-timeout=5",
              "--report-format=html",
              "--report-out",
              cli_report,
            ],
            stdout_io,
            stderr_io
          )
          code.should eq(0)
          stderr_io.to_s.includes?("--report-format supports only html or pdf").should be_false
          stderr_io.to_s.includes?("--wait-interval must be greater than 0").should be_false
          stderr_io.to_s.includes?("--wait-timeout must be 0 or greater").should be_false
        end
      end

      paths = server.requests.map(&.path)
      paths.includes?(Mzap::Client::SPIDER_STATUS).should be_true

      report_request = server.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should_not be_nil
      params = HTTP::Params.parse(report_request.not_nil!.query || "")
      full_path = File.expand_path(cli_report)
      params["template"].should eq("traditional-html")
      params["reportFileName"].should eq(File.basename(full_path))
      params["reportDir"].should eq(File.dirname(full_path))
    ensure
      server.close
    end
  end

  it "returns error when scan urls file cannot be read" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider", "--urls", "/tmp/mzap-missing-targets.txt"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("No such file").should be_true
  end

  it "accepts --config equals syntax with an existing path" do
    config_path = "#{File.tempname("mzap-cli-config")}.toml"
    File.write(config_path, "report_format = \"html\"\n")

    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    begin
      code = Mzap::CLI.run(["version", "--config=#{config_path}"], stdout_io, stderr_io)
      code.should eq(0)
      stdout_io.to_s.includes?("Using config file: #{config_path}").should be_true
    ensure
      File.delete(config_path) if File.exists?(config_path)
    end
  end

  it "accepts equals syntax for scan options and generates a pdf report" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"120"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    report_path = "#{File.tempname("mzap-cli-equals")}.pdf"
    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      with_target_file(["https://cli-equals.test"]) do |target_file|
        code = Mzap::CLI.run(
          [
            "spider",
            "--urls=#{target_file}",
            "--apis=#{server.url}",
            "--wait-interval=1",
            "--wait-timeout=5",
            "--report-format=PDF",
            "--report-out=#{report_path}",
          ],
          stdout_io,
          stderr_io
        )
        code.should eq(0)
      end

      report_request = server.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should_not be_nil
      params = HTTP::Params.parse(report_request.not_nil!.query || "")
      params["template"].should eq("traditional-pdf")
      params["reportFileName"].should eq(File.basename(File.expand_path(report_path)))
    ensure
      File.delete(report_path) if File.exists?(report_path)
      server.close
    end
  end

  it "uses the last report out flag value when repeated with mixed syntax" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"121"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    first_report = "#{File.tempname("mzap-cli-report-out-first")}.html"
    second_report = "#{File.tempname("mzap-cli-report-out-second")}.html"
    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      with_target_file(["https://cli-report-out.test"]) do |target_file|
        code = Mzap::CLI.run(
          [
            "spider",
            "--urls",
            target_file,
            "--apis=#{server.url}",
            "--report-format=html",
            "--report-out=#{first_report}",
            "--report-out",
            second_report,
          ],
          stdout_io,
          stderr_io
        )
        code.should eq(0)
      end

      report_request = server.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should_not be_nil
      params = HTTP::Params.parse(report_request.not_nil!.query || "")
      full_path = File.expand_path(second_report)
      params["reportFileName"].should eq(File.basename(full_path))
      params["reportDir"].should eq(File.dirname(full_path))
    ensure
      server.close
    end
  end

  it "runs ajaxspider via CLI and polls ajax status when wait is enabled" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::AJAX_SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"1"}))
      when Mzap::Client::AJAX_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"stopped"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      with_target_file(["https://cli-ajax-wait.test"]) do |target_file|
        code = Mzap::CLI.run(
          ["ajaxspider", "--urls", target_file, "--apis", server.url, "--wait"],
          stdout_io,
          stderr_io
        )
        code.should eq(0)
      end

      paths = server.requests.map(&.path)
      paths.includes?(Mzap::Client::AJAX_STATUS).should be_true
    ensure
      server.close
    end
  end

  it "runs ascan via CLI with report options and polls ascan status" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::ASCAN_API
        context.response.status_code = 200
        context.response.print(%({"scan":"66"}))
      when Mzap::Client::ASCAN_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      with_target_file(["https://cli-ascan-report.test"]) do |target_file|
        code = Mzap::CLI.run(
          ["ascan", "--urls", target_file, "--apis", server.url, "--report-format", "html"],
          stdout_io,
          stderr_io
        )
        code.should eq(0)
      end

      paths = server.requests.map(&.path)
      paths.includes?(Mzap::Client::ASCAN_STATUS).should be_true
      paths.includes?(Mzap::Client::REPORT_GENERATE_API).should be_true
    ensure
      server.close
    end
  end

  it "rescues unexpected exceptions during execution and returns 1" do
    stdout_io = RaisingIO.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version"], stdout_io, stderr_io)

    code.should eq(1)
    stderr_io.to_s.includes?("Mocked unexpected Exception").should be_true
  end
end
