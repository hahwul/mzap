require "./spec_helper"

describe Mzap::Config do
  it "uses ~/.config/mzap/config.toml as the default config path" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, "sample = true\n")

      loaded = Mzap::Config.load_options("")
      output = IO::Memory.new
      Mzap::Config.show_config_notice(loaded.path, output)

      output.to_s.includes?("Using config file: #{config_path}").should be_true
    end
  end

  it "falls back to legacy ~/.mzap.yaml when new default path is missing" do
    with_temp_home do |temp_home|
      legacy_path = File.join(temp_home, ".mzap.yaml")
      File.write(legacy_path, "sample: true\n")

      loaded = Mzap::Config.load_options("")
      output = IO::Memory.new
      Mzap::Config.show_config_notice(loaded.path, output)

      output.to_s.includes?("Using config file: #{legacy_path}").should be_true
    end
  end

  it "prefers ~/.config/mzap/config.toml over legacy config files" do
    with_temp_home do |temp_home|
      preferred_path = File.join(temp_home, ".config", "mzap", "config.toml")
      legacy_path = File.join(temp_home, ".mzap.yaml")
      Dir.mkdir_p(File.dirname(preferred_path))
      File.write(preferred_path, "sample = true\n")
      File.write(legacy_path, "sample: true\n")

      loaded = Mzap::Config.load_options("")
      output = IO::Memory.new
      Mzap::Config.show_config_notice(loaded.path, output)

      text = output.to_s
      text.includes?("Using config file: #{preferred_path}").should be_true
      text.includes?("Using config file: #{legacy_path}").should be_false
    end
  end

  it "keeps explicit non-toml config path without parsing runtime options" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, "custom.yaml")
      File.write(config_path, "wait: true\n")

      loaded = Mzap::Config.load_options(config_path)
      loaded.path.should eq(config_path)
      loaded.wait.should be_nil
      loaded.apis.should be_nil
    end
  end

  it "prefers extensionless ~/.mzap over extension variants" do
    with_temp_home do |temp_home|
      extensionless = File.join(temp_home, ".mzap")
      yaml_path = File.join(temp_home, ".mzap.yaml")
      File.write(extensionless, "raw config\n")
      File.write(yaml_path, "sample: true\n")

      loaded = Mzap::Config.load_options("")
      output = IO::Memory.new
      Mzap::Config.show_config_notice(loaded.path, output)

      output.to_s.includes?("Using config file: #{extensionless}").should be_true
      output.to_s.includes?("Using config file: #{yaml_path}").should be_false
    end
  end

  it "falls back to ~/.config/mzap/config.yaml when default toml is missing" do
    with_temp_home do |temp_home|
      yaml_path = File.join(temp_home, ".config", "mzap", "config.yaml")
      Dir.mkdir_p(File.dirname(yaml_path))
      File.write(yaml_path, "sample: true\n")

      loaded = Mzap::Config.load_options("")
      output = IO::Memory.new
      Mzap::Config.show_config_notice(loaded.path, output)

      output.to_s.includes?("Using config file: #{yaml_path}").should be_true
    end
  end

  it "falls back to extensionless ~/.config/mzap/config before legacy paths" do
    with_temp_home do |temp_home|
      default_base = File.join(temp_home, ".config", "mzap", "config")
      legacy_path = File.join(temp_home, ".mzap.yaml")
      Dir.mkdir_p(File.dirname(default_base))
      File.write(default_base, "base config\n")
      File.write(legacy_path, "legacy: true\n")

      loaded = Mzap::Config.load_options("")
      output = IO::Memory.new
      Mzap::Config.show_config_notice(loaded.path, output)

      text = output.to_s
      text.includes?("Using config file: #{default_base}").should be_true
      text.includes?("Using config file: #{legacy_path}").should be_false
    end
  end

  it "handles missing HOME by skipping auto config discovery" do
    previous_home = ENV["HOME"]?
    ENV.delete("HOME")

    begin
      loaded = Mzap::Config.load_options("")
      loaded.path.should be_nil

      output = IO::Memory.new
      Mzap::Config.show_config_notice(loaded.path, output)
      output.to_s.should eq("")
    ensure
      if previous_home
        ENV["HOME"] = previous_home
      end
    end
  end

  it "prints no notice for explicit config paths that do not exist" do
    output = IO::Memory.new
    missing_path = File.join(File.tempname("mzap-missing-config"), "config.toml")

    loaded = Mzap::Config.load_options(missing_path)
    Mzap::Config.show_config_notice(loaded.path, output)
    output.to_s.should eq("")
  end
end
