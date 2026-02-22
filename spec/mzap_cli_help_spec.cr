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

end
