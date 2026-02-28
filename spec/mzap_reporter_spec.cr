require "./spec_helper"

describe Mzap::Reporter do
  it "formats info output with optional context fields" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    reporter = Mzap::Reporter.new(stdout_io, stderr_io)

    reporter.info("spider", "added", "http://zap:8090", "https://target.test")

    stdout_io.to_s.includes?("[INFO] [spider] [http://zap:8090] [https://target.test] added").should be_true
    stderr_io.to_s.should eq("")
  end

  it "formats warn output without optional context fields" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    reporter = Mzap::Reporter.new(stdout_io, stderr_io)

    reporter.warn("wait", "timeout")

    stderr_io.to_s.includes?("[WARN] [wait] timeout").should be_true
    stdout_io.to_s.should eq("")
  end
end
