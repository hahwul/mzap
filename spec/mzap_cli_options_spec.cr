require "./spec_helper"

describe Mzap::CLI do
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

  it "returns error when apis equals syntax has empty value" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--apis="], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --apis").should be_true
  end

  it "returns error when apis value is followed by another flag" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--apis", "--wait"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --apis").should be_true
  end

  it "returns error for unsupported report format" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider", "--urls", "targets.txt", "--report-format", "xml"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("--report-format supports only html or pdf").should be_true
  end

  it "returns error for unknown option" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--unknown"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Unknown option: --unknown").should be_true
  end

  it "accepts dash-prefixed option value with equals syntax" do
    server = TestServer.new
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    begin
      code = Mzap::CLI.run(["stop", "spider", "--apis", server.url, "--apikey=-dash-key"], stdout_io, stderr_io)
      code.should eq(0)

      requests = server.requests
      requests.size.should eq(1)
      requests[0].api_key.should eq("-dash-key")
    ensure
      server.close
    end
  end

  it "returns error when string option value is missing" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider", "--urls", "--apis", "http://localhost:8090"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --urls").should be_true
  end

  it "returns error when report format value is missing" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider", "--urls", "targets.txt", "--report-format"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --report-format").should be_true
  end

  it "returns error when report output value is missing" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider", "--urls", "targets.txt", "--report-out"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --report-out").should be_true
  end

  it "returns error when wait interval value is missing" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--wait-interval"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --wait-interval").should be_true
  end

  it "returns error when report format is followed by another flag" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider", "--urls", "targets.txt", "--report-format", "--wait"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --report-format").should be_true
  end

  it "returns error when report format equals syntax has empty value" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider", "--urls", "targets.txt", "--report-format="], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --report-format").should be_true
  end

  it "returns error when report out equals syntax has empty value" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider", "--urls", "targets.txt", "--report-out="], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --report-out").should be_true
  end

  it "returns error when string option equals syntax has empty value" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider", "--urls=", "--apis", "http://localhost:8090"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --urls").should be_true
  end

  it "returns error for invalid wait interval integer" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--wait-interval", "abc"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Invalid integer for --wait-interval").should be_true
  end

  it "returns error for invalid wait interval integer in equals syntax" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--wait-interval=abc"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Invalid integer for --wait-interval").should be_true
  end

  it "returns error when wait interval is zero or negative" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--wait-interval", "0"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("--wait-interval must be greater than 0").should be_true

    stdout_io.clear
    stderr_io.clear
    code = Mzap::CLI.run(["version", "--wait-interval=-1"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("--wait-interval must be greater than 0").should be_true
  end

  it "returns error when wait timeout value is missing" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--wait-timeout"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --wait-timeout").should be_true
  end

  it "returns error when wait timeout is negative" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--wait-timeout", "-1"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("--wait-timeout must be 0 or greater").should be_true

    stdout_io.clear
    stderr_io.clear
    code = Mzap::CLI.run(["version", "--wait-timeout=-1"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("--wait-timeout must be 0 or greater").should be_true
  end

  it "returns error when report output is set without report format" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["spider", "--urls", "targets.txt", "--report-out", "report.html"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("--report-out requires --report-format").should be_true
  end

  it "returns error when wait/report options are used with non-scan commands" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--wait"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("--wait and report options are only available").should be_true
  end

  it "does not apply scan-only config options to non-scan commands" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(
        config_path,
        <<-TOML
        [mzap]
        wait = true
        report_format = "html"
        TOML
      )

      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      code = Mzap::CLI.run(["version"], stdout_io, stderr_io)
      code.should eq(0)
      stdout_io.to_s.includes?(Mzap::VERSION).should be_true
      stderr_io.to_s.includes?("only available for spider/ajaxspider/ascan").should be_false
    end
  end

  it "returns error when config value is missing" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--config"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --config").should be_true
  end

  it "returns error when config value is dash-prefixed in space syntax" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--config", "-tmp"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --config").should be_true
  end

  it "returns error when apikey value is missing" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--apikey"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --apikey").should be_true
  end

  it "returns error for invalid wait timeout integer" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--wait-timeout", "abc"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Invalid integer for --wait-timeout").should be_true
  end

  it "returns error when config equals syntax has empty value" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--config="], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --config").should be_true
  end

  it "returns error when apikey equals syntax has empty value" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--apikey="], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Please input value for --apikey").should be_true
  end

  it "returns error for invalid wait timeout integer in equals syntax" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--wait-timeout=abc"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Invalid integer for --wait-timeout").should be_true
  end

  it "returns error when config file parsing fails during CLI startup" do
    config_path = "#{File.tempname("mzap-invalid-config")}.toml"
    File.write(config_path, "wait = \"yes\"\n")

    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    begin
      code = Mzap::CLI.run(["version", "--config", config_path], stdout_io, stderr_io)
      code.should eq(1)
      stderr_io.to_s.includes?("Invalid TOML boolean").should be_true
      stdout_io.to_s.includes?("Using config file").should be_false
    ensure
      File.delete(config_path) if File.exists?(config_path)
    end
  end

  it "returns error when report format is used with non-scan command" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--report-format", "html"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("--wait and report options are only available").should be_true
  end

  it "returns error when report output and format are used with non-scan command" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--report-format", "pdf", "--report-out", "report.pdf"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("--wait and report options are only available").should be_true
  end

end
