require "./spec_helper"

describe Mzap do
  it "lists scan policy names per host" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 200
      if context.request.path == Mzap::Client::SCAN_POLICY_NAMES_API
        context.response.print(%({"scanPolicyNames":["Default Policy","API-Minimal-Scan"]}))
      else
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, IO::Memory.new)
      Mzap.list_policies(server.url, options: Mzap::Options.new, reporter: reporter)

      stdout = stdout_io.to_s
      stdout.includes?("scan policies: Default Policy, API-Minimal-Scan").should be_true
    ensure
      server.close
    end
  end

  it "reports scanner counts for a named policy" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 200
      if context.request.path == Mzap::Client::ASCAN_SCANNERS_API
        context.response.print(%({"scanners":[{"id":"1","enabled":"true"},{"id":"2","enabled":"false"}]}))
      else
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, IO::Memory.new)
      Mzap.list_policies(server.url, policy: "API-Minimal-Scan", options: Mzap::Options.new, reporter: reporter)

      requests = server.requests
      requests[0].path.should eq(Mzap::Client::ASCAN_SCANNERS_API)
      HTTP::Params.parse(requests[0].query || "")["scanPolicyName"].should eq("API-Minimal-Scan")
      stdout_io.to_s.includes?("2 scanner(s), 1 enabled").should be_true
    ensure
      server.close
    end
  end

  it "exports the sites tree with the given path" do
    server = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      Mzap.export_sites_tree(server.url, file_path: "baseline.tree", options: Mzap::Options.new(api_key: "k"), reporter: reporter)

      requests = server.requests
      requests.size.should eq(1)
      requests[0].path.should eq(Mzap::Client::EXPORT_SITES_TREE_API)
      HTTP::Params.parse(requests[0].query || "")["filePath"].should eq("baseline.tree")
      requests[0].api_key.should eq("k")
    ensure
      server.close
    end
  end

  it "prunes the sites tree with the given path" do
    server = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      Mzap.prune_sites_tree(server.url, file_path: "baseline.tree", options: Mzap::Options.new, reporter: reporter)

      requests = server.requests
      requests.size.should eq(1)
      requests[0].path.should eq(Mzap::Client::PRUNE_SITES_TREE_API)
      HTTP::Params.parse(requests[0].query || "")["filePath"].should eq("baseline.tree")
    ensure
      server.close
    end
  end

  it "namespaces sites tree paths per host across multiple hosts" do
    server1 = TestServer.new
    server2 = TestServer.new

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      Mzap.export_sites_tree("#{server1.url},#{server2.url}", file_path: "baseline.tree", options: Mzap::Options.new, reporter: reporter)

      path1 = HTTP::Params.parse(server1.requests[0].query || "")["filePath"]
      path2 = HTTP::Params.parse(server2.requests[0].query || "")["filePath"]
      path1.should_not eq(path2)
      path1.ends_with?(".tree").should be_true
      path2.ends_with?(".tree").should be_true
    ensure
      server1.close
      server2.close
    end
  end

  it "runs policies and sitestree via CLI" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      context.response.status_code = 200
      if context.request.path == Mzap::Client::SCAN_POLICY_NAMES_API
        context.response.print(%({"scanPolicyNames":["Default Policy"]}))
      else
        context.response.print(%({"ok":"true"}))
      end
    end)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new

      code = Mzap::CLI.run(["policies", "--apis", server.url], stdout_io, stderr_io)
      code.should eq(0)

      code = Mzap::CLI.run(["sitestree", "export", "baseline.tree", "--apis", server.url], stdout_io, stderr_io)
      code.should eq(0)

      paths = server.requests.map(&.path)
      paths.includes?(Mzap::Client::SCAN_POLICY_NAMES_API).should be_true
      paths.includes?(Mzap::Client::EXPORT_SITES_TREE_API).should be_true
    ensure
      server.close
    end
  end

  it "rejects an invalid sitestree action via CLI" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new

    code = Mzap::CLI.run(["sitestree", "bogus", "x.tree"], stdout_io, stderr_io)
    code.should eq(1)
    stdout_io.to_s.includes?("export/prune").should be_true
  end
end
