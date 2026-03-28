require "./spec_helper"

describe Mzap do
  it "waits for spider completion and requests filtered html report" do
    status_calls = 0
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"7"}))
      when Mzap::Client::SPIDER_STATUS
        status_calls += 1
        context.response.status_code = 200
        if status_calls < 2
          context.response.print(%({"status":"50"}))
        else
          context.response.print(%({"status":"100"}))
        end
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    report_path = "#{File.tempname("mzap-report")}.html"
    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://report.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 1, wait_timeout_seconds: 10, report_format: "html", report_out: report_path)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      requests = server.requests
      paths = requests.map(&.path)
      paths.includes?(Mzap::Client::SPIDER_STATUS).should be_true
      paths.includes?(Mzap::Client::REPORT_GENERATE_API).should be_true

      report_request = requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should_not be_nil
      params = HTTP::Params.parse(report_request.not_nil!.query || "")
      params["sites"].should eq("https://report.test")
      params["template"].should eq("traditional-html")
      params["reportFileName"].should eq(File.basename(File.expand_path(report_path)))
      params["reportDir"].should eq(File.dirname(File.expand_path(report_path)))
    ensure
      File.delete(report_path) if File.exists?(report_path)
      server.close
    end
  end

  it "falls back to core html report when reports add-on endpoint is unavailable" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"1"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 404
        context.response.print(%({"error":"missing"}))
      when Mzap::Client::HTML_REPORT_API
        context.response.status_code = 200
        context.response.print("<html>fallback report</html>")
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    report_path = "#{File.tempname("mzap-report")}.html"
    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://fallback.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 1, wait_timeout_seconds: 10, report_format: "html", report_out: report_path)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      requests = server.requests
      paths = requests.map(&.path)
      paths.includes?(Mzap::Client::REPORT_GENERATE_API).should be_true
      paths.includes?(Mzap::Client::HTML_REPORT_API).should be_true
      File.exists?(report_path).should be_true
      File.read(report_path).should eq("<html>fallback report</html>")
      reporter_output = stdout_io.to_s
      reporter_output.includes?("summary total=1 saved=0 fallback=1 failed=0").should be_true
    ensure
      File.delete(report_path) if File.exists?(report_path)
      server.close
    end
  end

  it "logs report failure reasons and report summary when all report endpoints fail" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"12"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 500
        context.response.print(%({"error":"filtered fail"}))
      when Mzap::Client::HTML_REPORT_API
        context.response.status_code = 500
        context.response.print(%({"error":"core fail"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    report_path = "#{File.tempname("mzap-report")}.html"
    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://report-fail.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 1, wait_timeout_seconds: 10, report_format: "html", report_out: report_path)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      stderr = stderr_io.to_s
      stdout = stdout_io.to_s
      stderr.includes?("filtered generation failed").should be_true
      stderr.includes?("HTTP 500").should be_true
      stdout.includes?("summary total=1 saved=0 fallback=0 failed=1").should be_true
    ensure
      File.delete(report_path) if File.exists?(report_path)
      server.close
    end
  end

  it "reports mixed saved fallback and failed summary counts across api hosts" do
    saved_server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"201"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    fallback_server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"202"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 404
        context.response.print(%({"error":"missing"}))
      when Mzap::Client::HTML_REPORT_API
        context.response.status_code = 200
        context.response.print("<html>fallback host report</html>")
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    failed_server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"203"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 500
        context.response.print(%({"error":"filtered fail"}))
      when Mzap::Client::HTML_REPORT_API
        context.response.status_code = 500
        context.response.print(%({"error":"core fail"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    report_dir = File.tempname("mzap-mixed-report")
    report_path = File.join(report_dir, "report.html")
    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://saved.test", "https://fallback.test", "https://failed.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, report_format: "html", report_out: report_path)
        Mzap.spider(target_file, apis: "#{saved_server.url},#{fallback_server.url},#{failed_server.url}", options: options, reporter: reporter)
      end

      stdout = stdout_io.to_s
      stderr = stderr_io.to_s
      stdout.includes?("summary total=3 saved=1 fallback=1 failed=1").should be_true
      stderr.includes?("filtered generation failed").should be_true
      stderr.includes?("HTTP 404").should be_true
      stderr.includes?("HTTP 500").should be_true

      fallback_file = File.join(
        File.dirname(File.expand_path(report_path)),
        "report-#{sanitized_host_for_report(fallback_server.url)}.html"
      )
      failed_file = File.join(
        File.dirname(File.expand_path(report_path)),
        "report-#{sanitized_host_for_report(failed_server.url)}.html"
      )
      File.exists?(fallback_file).should be_true
      File.exists?(failed_file).should be_false
    ensure
      FileUtils.rm_rf(report_dir)
      saved_server.close
      fallback_server.close
      failed_server.close
    end
  end

  it "normalizes report output extension to report format" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"9"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    report_path = "#{File.tempname("mzap-report")}.html"
    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://ext.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 1, wait_timeout_seconds: 10, report_format: "pdf", report_out: report_path)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      report_request = server.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should_not be_nil
      params = HTTP::Params.parse(report_request.not_nil!.query || "")
      full_path = File.expand_path(report_path)
      expected_name = "#{File.basename(full_path, File.extname(full_path))}.pdf"

      params["template"].should eq("traditional-pdf")
      params["reportFileName"].should eq(expected_name)
      params["reportDir"].should eq(File.dirname(full_path))
    ensure
      server.close
    end
  end

  it "generates host-specific report names for multiple api hosts" do
    handler = ->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"11"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end
    server1 = TestServer.new(handler)
    server2 = TestServer.new(handler)

    report_path = "#{File.tempname("mzap-report")}.html"
    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://one.test", "https://two.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 1, wait_timeout_seconds: 10, report_format: "pdf", report_out: report_path)
        Mzap.spider(target_file, apis: "#{server1.url},#{server2.url}", options: options, reporter: reporter)
      end

      full_path = File.expand_path(report_path)
      stem = File.basename(full_path, File.extname(full_path))
      expected1 = "#{stem}-#{sanitized_host_for_report(server1.url)}.pdf"
      expected2 = "#{stem}-#{sanitized_host_for_report(server2.url)}.pdf"
      expected_dir = File.dirname(full_path)

      report_request1 = server1.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request2 = server2.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request1.should_not be_nil
      report_request2.should_not be_nil

      params1 = HTTP::Params.parse(report_request1.not_nil!.query || "")
      params2 = HTTP::Params.parse(report_request2.not_nil!.query || "")
      params1["template"].should eq("traditional-pdf")
      params2["template"].should eq("traditional-pdf")
      params1["reportFileName"].should eq(expected1)
      params2["reportFileName"].should eq(expected2)
      params1["reportDir"].should eq(expected_dir)
      params2["reportDir"].should eq(expected_dir)
    ensure
      server1.close
      server2.close
    end
  end

  it "deduplicates host-specific report names when sanitized host values collide" do
    report_handler = ->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"15"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end

    server1 = TestServer.new(report_handler)
    server2 = TestServer.new(report_handler)
    server3 = TestServer.new(report_handler)

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://collision-one.test", "https://collision-two.test", "https://collision-three.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, report_format: "html", report_out: "collision-report")
        Mzap.spider(target_file, apis: "#{server1.url},#{server2.url},#{server3.url}", options: options, reporter: reporter)
      end

      all_requests = server1.requests + server2.requests + server3.requests
      report_requests = all_requests.select { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_requests.size.should eq(3)

      report_names = report_requests.map do |request|
        params = HTTP::Params.parse(request.query || "")
        params["reportFileName"]
      end

      safe_host1 = sanitized_host_for_report(server1.url)
      safe_host2 = sanitized_host_for_report(server2.url)
      safe_host3 = sanitized_host_for_report(server3.url)
      expected_names = [
        "collision-report-#{safe_host1}.html",
        "collision-report-#{safe_host2}.html",
        "collision-report-#{safe_host3}.html",
      ]
      report_names.sort.should eq(expected_names.sort)
    ensure
      server1.close
      server2.close
      server3.close
    end
  end

  it "uses default report output name when report_out is not provided" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"8"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://default-report.test"]) do |target_file|
        options = Mzap::Options.new(wait_interval_seconds: 0, wait_timeout_seconds: 5, report_format: "html")
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      report_request = server.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should_not be_nil
      params = HTTP::Params.parse(report_request.not_nil!.query || "")

      params["template"].should eq("traditional-html")
      params["reportDir"].should eq(File.expand_path("."))
      params["reportFileName"].starts_with?("mzap-report-").should be_true
      params["reportFileName"].ends_with?(".html").should be_true
    ensure
      server.close
    end
  end

  it "builds host-specific report names in cwd when output path has no directory" do
    handler = ->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"13"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end
    server1 = TestServer.new(handler)
    server2 = TestServer.new(handler)

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://one.test", "https://two.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, report_format: "pdf", report_out: "scan-report")
        Mzap.spider(target_file, apis: "#{server1.url},#{server2.url}", options: options, reporter: reporter)
      end

      expected1 = "scan-report-#{sanitized_host_for_report(server1.url)}.pdf"
      expected2 = "scan-report-#{sanitized_host_for_report(server2.url)}.pdf"
      expected_dir = File.expand_path(".")

      report_request1 = server1.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request2 = server2.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request1.should_not be_nil
      report_request2.should_not be_nil

      params1 = HTTP::Params.parse(report_request1.not_nil!.query || "")
      params2 = HTTP::Params.parse(report_request2.not_nil!.query || "")
      params1["reportFileName"].should eq(expected1)
      params2["reportFileName"].should eq(expected2)
      params1["reportDir"].should eq(expected_dir)
      params2["reportDir"].should eq(expected_dir)
    ensure
      server1.close
      server2.close
    end
  end

  it "deduplicates report sites for repeated targets on the same api host" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"31"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://dup.test", "https://dup.test", "https://unique.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, report_format: "html")
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      report_request = server.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should_not be_nil
      params = HTTP::Params.parse(report_request.not_nil!.query || "")
      params["sites"].should eq("https://dup.test|https://unique.test")
    ensure
      server.close
    end
  end

  it "falls back to core pdf report endpoint when filtered pdf report fails" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"61"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 404
        context.response.print(%({"error":"missing"}))
      when Mzap::Client::PDF_REPORT_API
        context.response.status_code = 200
        context.response.print("pdf fallback bytes")
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    report_path = "#{File.tempname("mzap-pdf-fallback")}.pdf"
    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://pdf-fallback.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, report_format: "pdf", report_out: report_path)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      paths = server.requests.map(&.path)
      paths.includes?(Mzap::Client::REPORT_GENERATE_API).should be_true
      paths.includes?(Mzap::Client::PDF_REPORT_API).should be_true
      File.exists?(report_path).should be_true
      File.read(report_path).should eq("pdf fallback bytes")
      stdout_io.to_s.includes?("fallback=1").should be_true
    ensure
      File.delete(report_path) if File.exists?(report_path)
      server.close
    end
  end

  it "keeps report output extension when it already matches format case-insensitively" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"71"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    report_path = "#{File.tempname("mzap-report-uppercased")}.HTML"
    begin
      reporter = Mzap::Reporter.new(IO::Memory.new, IO::Memory.new)
      with_target_file(["https://ext-case.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, report_format: "html", report_out: report_path)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      report_request = server.requests.find { |request| request.path == Mzap::Client::REPORT_GENERATE_API }
      report_request.should_not be_nil
      params = HTTP::Params.parse(report_request.not_nil!.query || "")
      params["reportFileName"].should eq(File.basename(File.expand_path(report_path)))
    ensure
      server.close
    end
  end

  it "reports report generation failure when output directory cannot be created" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"90"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 200
        context.response.print(%({"result":"ok"}))
      when Mzap::Client::HTML_REPORT_API
        context.response.status_code = 200
        context.response.print("<html>fallback</html>")
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    blocking_path = File.tempname("mzap-report-block")
    File.write(blocking_path, "block")
    report_path = File.join(blocking_path, "report.html")
    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://report-path-error.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, report_format: "html", report_out: report_path)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      stderr = stderr_io.to_s
      stdout = stdout_io.to_s
      stderr.includes?("filtered generation failed").should be_true
      stderr.includes?("error").should be_true
      stdout.includes?("summary total=1 saved=0 fallback=0 failed=1").should be_true
    ensure
      File.delete(blocking_path) if File.exists?(blocking_path)
      server.close
    end
  end

  it "creates nested directories when writing fallback core reports" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"44"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 404
        context.response.print(%({"error":"missing"}))
      when Mzap::Client::HTML_REPORT_API
        context.response.status_code = 200
        context.response.print("<html>nested fallback report</html>")
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    base_dir = File.tempname("mzap-report-nested")
    report_path = File.join(base_dir, "a", "b", "report.html")
    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://nested-fallback.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, report_format: "html", report_out: report_path)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      File.exists?(report_path).should be_true
      File.read(report_path).should eq("<html>nested fallback report</html>")
      stdout_io.to_s.includes?("fallback=1").should be_true
    ensure
      FileUtils.rm_rf(base_dir)
      server.close
    end
  end

  it "reports core report fallback generation failure when output file cannot be written" do
    server = TestServer.new(->(context : HTTP::Server::Context) do
      case context.request.path
      when Mzap::Client::ACCESS_API
        context.response.status_code = 200
        context.response.print(%({"ok":"true"}))
      when Mzap::Client::SPIDER_API
        context.response.status_code = 200
        context.response.print(%({"scan":"99"}))
      when Mzap::Client::SPIDER_STATUS
        context.response.status_code = 200
        context.response.print(%({"status":"100"}))
      when Mzap::Client::REPORT_GENERATE_API
        context.response.status_code = 404
        context.response.print(%({"error":"missing"}))
      when Mzap::Client::HTML_REPORT_API
        context.response.status_code = 200
        context.response.print("<html>core report</html>")
      else
        context.response.status_code = 404
        context.response.print(%({"error":"not found"}))
      end
    end)

    blocking_dir = File.tempname("mzap-core-report-block")
    Dir.mkdir_p(blocking_dir)
    # The normalisation appends ".html" to the directory path if it doesn't end with it,
    # so we need to create a directory with the exact final output path name
    blocking_dir_with_ext = "#{blocking_dir}.html"
    Dir.mkdir_p(blocking_dir_with_ext)

    begin
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      reporter = Mzap::Reporter.new(stdout_io, stderr_io)
      with_target_file(["https://core-report-path-error.test"]) do |target_file|
        options = Mzap::Options.new(wait_for_completion: true, wait_interval_seconds: 0, wait_timeout_seconds: 5, report_format: "html", report_out: blocking_dir_with_ext)
        Mzap.spider(target_file, apis: server.url, options: options, reporter: reporter)
      end

      stderr = stderr_io.to_s
      stdout = stdout_io.to_s
      stderr.includes?("error").should be_true
      stderr.includes?("Is a directory").should be_true
      stdout.includes?("summary total=1 saved=0 fallback=0 failed=1").should be_true
    ensure
      FileUtils.rm_rf(blocking_dir)
      FileUtils.rm_rf(blocking_dir_with_ext)
      server.close
    end
  end
end
