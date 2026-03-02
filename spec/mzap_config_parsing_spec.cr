require "./spec_helper"

describe Mzap::Config do
  it "loads runtime options from TOML config" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(
        config_path,
        <<-TOML
        [mzap]
        apis = ["http://127.0.0.1:8090", "http://127.0.0.2:8090"]
        apikey = "cfg-key"
        urls = "samples/target.txt"
        wait = true
        wait_interval = 3
        wait_timeout = 20
        report_format = "html"
        report_out = "reports/mzap.html"
        TOML
      )

      loaded = Mzap::Config.load_options("")
      loaded.path.should eq(config_path)
      loaded.apis.should eq("http://127.0.0.1:8090,http://127.0.0.2:8090")
      loaded.api_key.should eq("cfg-key")
      loaded.urls.should eq("samples/target.txt")
      loaded.wait.should eq(true)
      loaded.wait_interval_seconds.should eq(3)
      loaded.wait_timeout_seconds.should eq(20)
      loaded.report_format.should eq("html")
      loaded.report_out.should eq("reports/mzap.html")
    end
  end

  it "raises an error for invalid TOML option types" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, "wait = \"yes\"\n")

      expect_raises(ArgumentError, /Invalid TOML boolean/) do
        Mzap::Config.load_options("")
      end
    end
  end

  it "returns empty FileOptions without errors for an empty TOML config" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, "")

      loaded = Mzap::Config.load_options("")
      loaded.path.should eq(config_path)
      loaded.apis.should be_nil
      loaded.api_key.should be_nil
      loaded.urls.should be_nil
      loaded.wait.should be_nil
      loaded.wait_interval_seconds.should be_nil
      loaded.wait_timeout_seconds.should be_nil
      loaded.report_format.should be_nil
      loaded.report_out.should be_nil
    end
  end

  it "loads root-level keys and ignores unrelated tables" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(
        config_path,
        <<-TOML
        urls = "root-targets.txt"
        [other]
        apis = "http://ignored:8090"
        [mzap]
        apis = "http://127.0.0.1:8090"
        TOML
      )

      loaded = Mzap::Config.load_options("")
      loaded.urls.should eq("root-targets.txt")
      loaded.apis.should eq("http://127.0.0.1:8090")
    end
  end

  it "normalizes quoted and mzap-prefixed TOML keys" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(
        config_path,
        <<-TOML
        "mzap.apikey" = "prefixed-key"
        'mzap.wait-timeout' = 12
        "report-format" = "pdf"
        TOML
      )

      loaded = Mzap::Config.load_options("")
      loaded.api_key.should eq("prefixed-key")
      loaded.wait_timeout_seconds.should eq(12)
      loaded.report_format.should eq("pdf")
    end
  end

  it "parses case-insensitive TOML booleans and underscored integers" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(
        config_path,
        <<-TOML
        wait = TRUE
        wait_interval_seconds = 1_5
        TOML
      )

      loaded = Mzap::Config.load_options("")
      loaded.wait.should eq(true)
      loaded.wait_interval_seconds.should eq(15)
    end
  end

  it "raises an error for invalid TOML syntax without assignment" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, "wait true\n")

      expect_raises(ArgumentError, /Invalid TOML syntax/) do
        Mzap::Config.load_options("")
      end
    end
  end

  it "raises an error for invalid TOML array items" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, "apis = [,\"http://127.0.0.1:8090\"]\n")

      expect_raises(ArgumentError, /Invalid TOML array item/) do
        Mzap::Config.load_options("")
      end
    end
  end

  it "preserves # and = characters inside quoted TOML strings" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(
        config_path,
        <<-TOML
        report_out = "reports/a=b#daily.html" # keep only trailing comment outside quotes
        urls = "https://example.test/path?a=1#frag"
        TOML
      )

      loaded = Mzap::Config.load_options("")
      loaded.report_out.should eq("reports/a=b#daily.html")
      loaded.urls.should eq("https://example.test/path?a=1#frag")
    end
  end

  it "parses options from mixed-case mzap table name" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(
        config_path,
        <<-TOML
        [MZAP]
        apikey = "upper-table-key"
        wait_timeout_seconds = 9
        TOML
      )

      loaded = Mzap::Config.load_options("")
      loaded.api_key.should eq("upper-table-key")
      loaded.wait_timeout_seconds.should eq(9)
    end
  end

  it "ignores unknown TOML keys without failing" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(
        config_path,
        <<-TOML
        unknown_flag = "value"
        report_format = "html"
        TOML
      )

      loaded = Mzap::Config.load_options("")
      loaded.report_format.should eq("html")
      loaded.urls.should be_nil
      loaded.apis.should be_nil
    end
  end

  it "raises an error for TOML entries with empty keys" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, " = \"value\"\n")

      expect_raises(ArgumentError, /Invalid TOML key/) do
        Mzap::Config.load_options("")
      end
    end
  end

  it "raises an error for TOML entries with empty values" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, "urls = # missing value\n")

      expect_raises(ArgumentError, /Invalid TOML value for urls/) do
        Mzap::Config.load_options("")
      end
    end
  end

  it "raises an error for unquoted TOML string values" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, "urls = not_a_string_literal\n")

      expect_raises(ArgumentError, /Invalid TOML string for urls/) do
        Mzap::Config.load_options("")
      end
    end
  end

  it "parses single-quoted TOML string values" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(
        config_path,
        <<-TOML
        apis = 'http://127.0.0.1:8090'
        report_out = 'reports/single-quoted.html'
        TOML
      )

      loaded = Mzap::Config.load_options("")
      loaded.apis.should eq("http://127.0.0.1:8090")
      loaded.report_out.should eq("reports/single-quoted.html")
    end
  end

  it "parses false boolean and empty apis array values" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(
        config_path,
        <<-TOML
        wait = false
        apis = []
        TOML
      )

      loaded = Mzap::Config.load_options("")
      loaded.wait.should eq(false)
      loaded.apis.should eq("")
    end
  end

  it "raises an error for invalid TOML arrays with unclosed quotes" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, "apis = [\"http://127.0.0.1:8090]\n")

      expect_raises(ArgumentError, /Invalid TOML array/) do
        Mzap::Config.load_options("")
      end
    end
  end

  it "raises an error for invalid TOML string escape sequences" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, "urls = \"bad\\xescape\"\n")

      expect_raises(ArgumentError, /Invalid TOML string for urls/) do
        Mzap::Config.load_options("")
      end
    end
  end

  it "raises an error for invalid TOML integer values" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, "wait_timeout = 1two\n")

      expect_raises(ArgumentError, /Invalid TOML integer for wait_timeout/) do
        Mzap::Config.load_options("")
      end
    end
  end

  it "raises an error for non-string values in apis arrays" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, "apis = [\"http://127.0.0.1:8090\", 5]\n")

      expect_raises(ArgumentError, /Invalid TOML string for apis/) do
        Mzap::Config.load_options("")
      end
    end
  end

  it "accepts TOML arrays with trailing commas for apis" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, "apis = [\"http://127.0.0.1:8090\",]\n")

      loaded = Mzap::Config.load_options("")
      loaded.apis.should eq("http://127.0.0.1:8090")
    end
  end

  it "preserves # characters inside single-quoted TOML strings" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, "urls = 'https://single-quote.test/path#frag' # trailing comment\n")

      loaded = Mzap::Config.load_options("")
      loaded.urls.should eq("https://single-quote.test/path#frag")
    end
  end

  it "raises an error for TOML arrays missing closing brackets" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, "apis = [\"http://127.0.0.1:8090\"\n")

      expect_raises(ArgumentError, /Invalid TOML array/) do
        Mzap::Config.load_options("")
      end
    end
  end

  it "parses escaped characters in double-quoted TOML strings" do
    with_temp_home do |temp_home|
      config_path = File.join(temp_home, ".config", "mzap", "config.toml")
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, "report_out = \"reports\\\\daily\\nreport.html\"\n")

      loaded = Mzap::Config.load_options("")
      loaded.report_out.should eq("reports\\daily\nreport.html")
    end
  end
end
