require "./spec_helper"

describe Mzap::Options do
  it "enables wait when wait_for_completion is set" do
    options = Mzap::Options.new(wait_for_completion: true)
    options.wait_enabled?.should eq(true)
    options.report_enabled?.should eq(false)
  end

  it "enables wait automatically when report format is set" do
    options = Mzap::Options.new(report_format: "html")
    options.wait_enabled?.should eq(true)
    options.report_enabled?.should eq(true)
  end

  it "disables wait and report when neither flag is set" do
    options = Mzap::Options.new
    options.wait_enabled?.should eq(false)
    options.report_enabled?.should eq(false)
  end
end
