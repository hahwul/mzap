require "./spec_helper"

describe Mzap::Banner do
  it "prints banner text with project name and version" do
    output = IO::Memory.new

    Mzap::Banner.show(output)

    text = output.to_s
    text.includes?("MZAP").should be_true
    text.includes?(Mzap::VERSION).should be_true
    text.includes?("Multiple target/agent ZAP scanning").should be_true
  end
end
