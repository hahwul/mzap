require "./spec_helper"

describe Mzap::CLI do
  it "prints version and banner" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version"], stdout_io, stderr_io)
    code.should eq(0)
    stdout_io.to_s.includes?(Mzap::VERSION).should be_true
    stderr_io.to_s.includes?("MZAP").should be_true
  end

  it "prints help and succeeds when no command is provided" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run([] of String, stdout_io, stderr_io)
    code.should eq(0)
    stdout_io.to_s.includes?("Usage:").should be_true
  end

  it "prints help and succeeds when --help flag is provided" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--help"], stdout_io, stderr_io)
    code.should eq(0)
    stdout_io.to_s.includes?("Usage:").should be_true
    stdout_io.to_s.includes?(Mzap::VERSION).should be_false
  end

  it "prints help and succeeds when -h flag is provided" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["-h"], stdout_io, stderr_io)
    code.should eq(0)
    stdout_io.to_s.includes?("Usage:").should be_true
  end

  it "prints help text for help command" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["help"], stdout_io, stderr_io)
    code.should eq(0)
    stdout_io.to_s.includes?("Usage:").should be_true
    stdout_io.to_s.includes?("Subcommands:").should be_true
  end

  it "prints help even when scan-only flags are present with --help" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["version", "--help", "--wait", "--report-format", "html"], stdout_io, stderr_io)
    code.should eq(0)
    stdout_io.to_s.includes?("Usage:").should be_true
    stderr_io.to_s.includes?("only available for spider/ajaxspider/ascan").should be_false
  end

  it "prints spider-specific help for help spider" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["help", "spider"], stdout_io, stderr_io)
    code.should eq(0)
    stdout = stdout_io.to_s
    stdout.includes?("Start Spider scans in ZAP").should be_true
    stdout.includes?("mzap spider --urls <file>").should be_true
    stdout.includes?("Subcommands:").should be_false
  end

  it "prints ajaxspider-specific help for help ajaxspider" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["help", "ajaxspider"], stdout_io, stderr_io)
    code.should eq(0)
    stdout = stdout_io.to_s
    stdout.includes?("Start Ajax Spider scans in ZAP").should be_true
    stdout.includes?("mzap ajaxspider --urls <file>").should be_true
  end

  it "prints ascan-specific help for help ascan" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["help", "ascan"], stdout_io, stderr_io)
    code.should eq(0)
    stdout = stdout_io.to_s
    stdout.includes?("Start Active Scan jobs in ZAP").should be_true
    stdout.includes?("mzap ascan --urls <file>").should be_true
  end

  it "prints stop-specific help for help stop" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["help", "stop"], stdout_io, stderr_io)
    code.should eq(0)
    stdout = stdout_io.to_s
    stdout.includes?("Stop running scans").should be_true
    stdout.includes?("mzap stop <type>").should be_true
    stdout.includes?("spider").should be_true
    stdout.includes?("all").should be_true
  end

  it "prints version-specific help for help version" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["help", "version"], stdout_io, stderr_io)
    code.should eq(0)
    stdout = stdout_io.to_s
    stdout.includes?("Show mzap version").should be_true
    stdout.includes?("mzap version").should be_true
  end

  it "returns error for help with unknown subcommand" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["help", "nonexistent"], stdout_io, stderr_io)
    code.should eq(1)
    stdout = stdout_io.to_s
    stdout.includes?("Unknown command: nonexistent").should be_true
    stdout.includes?("Subcommands:").should be_true
  end

  it "returns unknown option error even when --help is present" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["--help", "--unknown=value"], stdout_io, stderr_io)
    code.should eq(1)
    stderr_io.to_s.includes?("Unknown option: --unknown=value").should be_true
    stdout_io.to_s.includes?("Usage:").should be_false
  end
end
