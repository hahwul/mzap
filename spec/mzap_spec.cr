require "./spec_helper"

describe Mzap do
  describe "module wrapper methods" do
    it "delegates spider to Mzap::Client" do
      server = TestServer.new
      begin
        reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
        with_target_file(["https://target.test"]) do |target_file|
          options = Mzap::Options.new("key", target_file)
          Mzap.spider(target_file, server.url, options, reporter)
        end
        requests = server.requests
        requests.size.should be > 0
        requests.map(&.path).includes?(Mzap::Client::SPIDER_API).should be_true
      ensure
        server.close
      end
    end

    it "delegates ajax_spider to Mzap::Client" do
      server = TestServer.new
      begin
        reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
        with_target_file(["https://target.test"]) do |target_file|
          options = Mzap::Options.new("key", target_file)
          Mzap.ajax_spider(target_file, server.url, options, reporter)
        end
        requests = server.requests
        requests.size.should be > 0
        requests.map(&.path).includes?(Mzap::Client::AJAX_SPIDER_API).should be_true
      ensure
        server.close
      end
    end

    it "delegates active_scan to Mzap::Client" do
      server = TestServer.new
      begin
        reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
        with_target_file(["https://target.test"]) do |target_file|
          options = Mzap::Options.new("key", target_file)
          Mzap.active_scan(target_file, server.url, options, reporter)
        end
        requests = server.requests
        requests.size.should be > 0
        requests.map(&.path).includes?(Mzap::Client::ASCAN_API).should be_true
      ensure
        server.close
      end
    end

    it "delegates stop_spider to Mzap::Client" do
      server = TestServer.new
      begin
        reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
        options = Mzap::Options.new("key", "")
        Mzap.stop_spider(server.url, options, reporter)
        requests = server.requests
        requests.size.should be > 0
        requests.map(&.path).includes?(stop_path(Mzap::Client::SPIDER_STOP)).should be_true
      ensure
        server.close
      end
    end

    it "delegates stop_active_scan to Mzap::Client" do
      server = TestServer.new
      begin
        reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
        options = Mzap::Options.new("key", "")
        Mzap.stop_active_scan(server.url, options, reporter)
        requests = server.requests
        requests.size.should be > 0
        requests.map(&.path).includes?(stop_path(Mzap::Client::ASCAN_STOP)).should be_true
      ensure
        server.close
      end
    end

    it "delegates stop_ajax_spider to Mzap::Client" do
      server = TestServer.new
      begin
        reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
        options = Mzap::Options.new("key", "")
        Mzap.stop_ajax_spider(server.url, options, reporter)
        requests = server.requests
        requests.size.should be > 0
        requests.map(&.path).includes?(stop_path(Mzap::Client::AJAX_SPIDER_STOP)).should be_true
      ensure
        server.close
      end
    end
  end
end
