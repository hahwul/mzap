require "./spec_helper"

CONTEXT_IMPORT_PATH = "/JSON/context/action/importContext/"

describe Mzap do
  it "imports context file before scanning" do
    server = TestServer.new

    context_file = File.tempname("mzap-context", ".context")
    File.write(context_file, "<configuration/>")

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://context.test"]) do |target_file|
        options = Mzap::Options.new(context: context_file)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      requests = server.requests
      context_request = requests.find { |r| r.path == CONTEXT_IMPORT_PATH }
      context_request.should_not be_nil
      params = HTTP::Params.parse(context_request.not_nil!.query || "")
      params["contextFile"].should eq(File.expand_path(context_file))

      spider_requests = requests.select { |r| r.path == Mzap::Client::SPIDER_API }
      spider_requests.size.should eq(1)
    ensure
      File.delete(context_file) if File.exists?(context_file)
      server.close
    end
  end

  it "imports context to all ZAP hosts" do
    server1 = TestServer.new
    server2 = TestServer.new

    context_file = File.tempname("mzap-context", ".context")
    File.write(context_file, "<configuration/>")

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://ctx1.test", "https://ctx2.test"]) do |target_file|
        options = Mzap::Options.new(context: context_file)
        Mzap.spider(target_file, apis: "#{server1.url},#{server2.url}", options: options, reporter: reporter)
      end

      ctx1 = server1.requests.find { |r| r.path == CONTEXT_IMPORT_PATH }
      ctx2 = server2.requests.find { |r| r.path == CONTEXT_IMPORT_PATH }
      ctx1.should_not be_nil
      ctx2.should_not be_nil
    ensure
      File.delete(context_file) if File.exists?(context_file)
      server1.close
      server2.close
    end
  end

  it "skips context import when not specified" do
    server = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://no-ctx.test"]) do |target_file|
        options = Mzap::Options.new
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      context_request = server.requests.find { |r| r.path == CONTEXT_IMPORT_PATH }
      context_request.should be_nil
    ensure
      server.close
    end
  end

  it "warns when context import fails and continues scanning" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when CONTEXT_IMPORT_PATH
        context.response.status_code = 500
        context.response.print(%({"error":"import failed"}))
      else
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      end
    end)

    context_file = File.tempname("mzap-context", ".context")
    File.write(context_file, "<configuration/>")

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://ctx-fail.test"]) do |target_file|
        options = Mzap::Options.new(context: context_file)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      stderr_io.to_s.includes?("import failed").should be_true
      spider_requests = server.requests.select { |r| r.path == Mzap::Client::SPIDER_API }
      spider_requests.size.should eq(1)
    ensure
      File.delete(context_file) if File.exists?(context_file)
      server.close
    end
  end

  it "rejects missing context file via CLI" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    code = Mzap::CLI.run(
      ["spider", "--urls", "targets.txt", "--context", "/nonexistent/context.xml"],
      stdout_io,
      stderr_io
    )
    code.should eq(1)
    stderr_io.to_s.includes?("Context file not found").should be_true
  end

  it "accepts --context via CLI" do
    server = TestServer.new

    context_file = File.tempname("mzap-cli-ctx", ".context")
    File.write(context_file, "<configuration/>")

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      with_target_file(["https://cli-ctx.test"]) do |target_file|
        code = Mzap::CLI.run(
          ["spider", "--urls", target_file, "--apis", server.url, "--context", context_file],
          stdout_io,
          stderr_io
        )
        code.should eq(0)
      end

      context_request = server.requests.find { |r| r.path == CONTEXT_IMPORT_PATH }
      context_request.should_not be_nil
    ensure
      File.delete(context_file) if File.exists?(context_file)
      server.close
    end
  end
end
