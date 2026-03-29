require "zap"
require "sarif"
require "set"

module Mzap
  module Client
    extend self

    ACCESS_API      = "/JSON/core/action/accessUrl/"
    SPIDER_API      = "/JSON/spider/action/scan/"
    ASCAN_API       = "/JSON/ascan/action/scan/"
    AJAX_SPIDER_API = "/JSON/ajaxSpider/action/scan/"
    SPIDER_STATUS   = "/JSON/spider/view/status/"
    ASCAN_STATUS    = "/JSON/ascan/view/status/"
    AJAX_STATUS     = "/JSON/ajaxSpider/view/status/"

    PSCAN_RECORDS_TO_SCAN = "/JSON/pscan/view/recordsToScan/"

    SPIDER_STOP      = "/JSON/spider/action/stopAllScans/"
    ASCAN_STOP       = "/JSON/ascan/action/stopAllScans/"
    AJAX_SPIDER_STOP = "/JSON/ajaxSpider/action/stop/"

    REPORT_GENERATE_API = "/JSON/reports/action/generate/"
    HTML_REPORT_API     = "/OTHER/core/other/htmlreport/"
    PDF_REPORT_API      = "/OTHER/core/other/pdfreport/"

    REPORT_TITLE  = "mzap report"
    TEMPLATE_HTML = "traditional-html"
    TEMPLATE_PDF  = "traditional-pdf"
    TEMPLATE_JSON = "traditional-json"
    TEMPLATE_MD   = "traditional-md"

    RUNNING_STATUSES = {"running", "inprogress", "in_progress", "started", "busy"}
    ERROR_STATUSES   = {"error", "failed", "failure", "aborted"}

    private record ScanJob, type : String, api_host : String, target : String, scan_id : String, zap_client : Zap::Client
    private record WaitPollResult, completed : Bool, failure_reason : String?

    def spider(urls : String, *, apis : String, options : Options, reporter : Reporter = Reporter.new) : Bool
      run(urls, apis, "spider", options, reporter)
    end

    def ajax_spider(urls : String, *, apis : String, options : Options, reporter : Reporter = Reporter.new) : Bool
      run(urls, apis, "ajax-spider", options, reporter)
    end

    def active_scan(urls : String, *, apis : String, options : Options, reporter : Reporter = Reporter.new) : Bool
      run(urls, apis, "active-scan", options, reporter)
    end

    def passive_scan(apis : String, *, options : Options, reporter : Reporter = Reporter.new) : Bool
      reporter.info("passive-scan", "start")

      api_hosts = normalize_api_hosts(apis)
      with_zap_clients(api_hosts, options) do |clients|
        pending = api_hosts.uniq.map { |host| {host, clients[host]} }
        reporter.info("passive-scan", "waiting for #{pending.size} host(s)")

        started_at = Time.utc
        poll_failures = 0
        completed_hosts = 0
        timed_out = false
        last_poll_failure = {} of String => String

        loop do
          pending.reject! do |(api_host, zap_client)|
            completed, failed = poll_pscan_status(api_host, zap_client, reporter, last_poll_failure)
            completed_hosts += 1 if completed
            poll_failures += 1 if failed
            completed
          end

          break if pending.empty?

          if wait_timeout?(started_at, options.wait_timeout_seconds)
            timed_out = true
            pending.each do |(api_host, _)|
              reporter.warn("passive-scan", "timeout", api_host)
            end
            break
          end

          sleep Math.max(options.wait_interval_seconds, 1).seconds
        end

        reporter.info("passive-scan", "summary completed=#{completed_hosts}/#{api_hosts.uniq.size} poll_failures=#{poll_failures} timed_out=#{timed_out}")

        if options.report_enabled?
          report_targets = Hash(String, Set(String)).new { |h, k| h[k] = Set(String).new }
          api_hosts.uniq.each { |host| report_targets[host] = Set(String).new }
          generate_reports(report_targets, clients, options, reporter)
        end

        if !options.fail_on.empty?
          return check_fail_on(clients, options, reporter)
        end
      end
      false
    end

    def stop_spider(apis : String, *, options : Options, reporter : Reporter = Reporter.new) : Nil
      stop_all(apis, "spider", options, reporter)
    end

    def stop_active_scan(apis : String, *, options : Options, reporter : Reporter = Reporter.new) : Nil
      stop_all(apis, "active-scan", options, reporter)
    end

    def stop_ajax_spider(apis : String, *, options : Options, reporter : Reporter = Reporter.new) : Nil
      stop_all(apis, "ajax-spider", options, reporter)
    end

    def run(urls : String, apis : String, scan_type : String, options : Options, reporter : Reporter = Reporter.new) : Bool
      reporter.info(scan_type, "start")

      unless File.exists?(urls)
        reporter.warn(scan_type, "target file not found", urls)
        return false
      end

      targets = [] of String
      seen = Set(String).new
      duplicates_removed = 0
      File.each_line(urls) do |line|
        value = line.strip
        next if value.empty?
        next if value.starts_with?('#')
        if seen.add?(value)
          targets << value
        else
          duplicates_removed += 1
        end
      end

      if targets.empty? && duplicates_removed == 0
        reporter.warn(scan_type, "no targets loaded from file", urls)
        return false
      end

      if duplicates_removed > 0
        reporter.warn(scan_type, "removed #{duplicates_removed} duplicate target(s)")
      end

      api_hosts = normalize_api_hosts(apis)
      with_zap_clients(api_hosts, options) do |clients|
        if !options.context.empty?
          import_context(clients, options.context, reporter)
        end

        scan_jobs = [] of ScanJob
        ajax_wait_clients = Hash(String, Zap::Client).new
        report_targets_by_api = Hash(String, Set(String)).new { |hash, key| hash[key] = Set(String).new }
        access_errors = 0
        scan_errors = 0
        scan_success = 0

        dispatch_targets = targets.map_with_index do |target, i|
          {target, api_hosts[i % api_hosts.size]}
        end

        if options.concurrency <= 1
          dispatch_targets.each do |(target, api_host)|
            ae, se, ss = dispatch_single_target(clients[api_host], api_host, target, scan_type, options, scan_jobs, ajax_wait_clients, report_targets_by_api, reporter)
            access_errors += ae
            scan_errors += se
            scan_success += ss
          end
        else
          mutex = Mutex.new
          done = Channel(Nil).new
          semaphore = Channel(Nil).new(options.concurrency)
          options.concurrency.times { semaphore.send(nil) }

          dispatch_targets.each do |(target, api_host)|
            semaphore.receive
            spawn do
              fiber_client = Zap::Client.new(base_url: api_host, api_key: options.api_key)
              begin
                ae, se, ss = dispatch_single_target(fiber_client, api_host, target, scan_type, options, scan_jobs, ajax_wait_clients, report_targets_by_api, reporter, mutex, clients[api_host])
                mutex.synchronize do
                  access_errors += ae
                  scan_errors += se
                  scan_success += ss
                end
              ensure
                fiber_client.close
                semaphore.send(nil)
                done.send(nil)
              end
            end
          end

          dispatch_targets.size.times { done.receive }
        end

        reporter.info(scan_type, "summary targets=#{targets.size} success=#{scan_success} scan_errors=#{scan_errors} access_errors=#{access_errors}")

        if options.wait_enabled?
          wait_for_completion(scan_jobs, ajax_wait_clients, options, reporter)
        end

        if options.report_enabled?
          generate_reports(report_targets_by_api, clients, options, reporter)
        end

        if !options.fail_on.empty?
          return check_fail_on(clients, options, reporter)
        end
      end
      false
    end

    private def dispatch_single_target(
      zap_client : Zap::Client,
      api_host : String,
      target : String,
      scan_type : String,
      options : Options,
      scan_jobs : Array(ScanJob),
      ajax_wait_clients : Hash(String, Zap::Client),
      report_targets_by_api : Hash(String, Set(String)),
      reporter : Reporter,
      mutex : Mutex? = nil,
      wait_client : Zap::Client? = nil,
    ) : {Int32, Int32, Int32}
      access_errors = 0
      scan_errors = 0
      scan_success = 0

      begin
        zap_client.core.access_url(target)
      rescue ex : Exception
        access_errors = 1
        reporter.warn(scan_type, "error (access) #{format_error(ex)}", api_host, target)
      end

      begin
        result = execute_scan(zap_client, scan_type, target, options.policy)
        scan_success = 1
        job_client = wait_client || zap_client
        if mutex
          mutex.synchronize do
            report_targets_by_api[api_host] << target
            collect_wait_job(scan_type, api_host, target, result, job_client, options, scan_jobs, ajax_wait_clients, reporter)
          end
        else
          report_targets_by_api[api_host] << target
          collect_wait_job(scan_type, api_host, target, result, job_client, options, scan_jobs, ajax_wait_clients, reporter)
        end
        reporter.info(scan_type, "added", api_host, target)
      rescue ex : Exception
        scan_errors = 1
        reporter.warn(scan_type, "error (scan) #{format_error(ex)}", api_host, target)
      end

      {access_errors, scan_errors, scan_success}
    end

    private def collect_wait_job(
      scan_type : String,
      api_host : String,
      target : String,
      result : JSON::Any,
      zap_client : Zap::Client,
      options : Options,
      scan_jobs : Array(ScanJob),
      ajax_wait_clients : Hash(String, Zap::Client),
      reporter : Reporter,
    ) : Nil
      return unless options.wait_enabled?
      case scan_type
      when "spider", "active-scan"
        scan_id = extract_scan_id(result)
        if scan_id
          scan_jobs << ScanJob.new(scan_type, api_host, target, scan_id, zap_client)
        else
          reporter.warn(scan_type, "missing scan id (wait disabled for target)", api_host, target)
        end
      when "ajax-spider"
        ajax_wait_clients[api_host] = zap_client
      end
    end

    RISK_LEVELS = {"informational" => 0, "low" => 1, "medium" => 2, "high" => 3}

    private def check_fail_on(clients : Hash(String, Zap::Client), options : Options, reporter : Reporter) : Bool
      min_risk = RISK_LEVELS[options.fail_on]? || 0
      failed = false

      clients.each do |api_host, zap_client|
        begin
          result = zap_client.alert.alerts
          alerts = extract_alerts_array(result)
          matching = alerts.count do |alert|
            alert_hash = alert.as_h? || next false
            risk_str = alert_hash["risk"]?.try(&.as_s?) || ""
            risk_id = RISK_LEVELS[risk_str.downcase]? || 0
            risk_id >= min_risk
          end

          if matching > 0
            failed = true
            reporter.warn("fail-on", "#{matching} alert(s) at or above #{options.fail_on} level", api_host)
          else
            reporter.info("fail-on", "no alerts at or above #{options.fail_on} level", api_host)
          end
        rescue ex : Exception
          reporter.warn("fail-on", "alert check failed #{format_error(ex)}", api_host)
        end
      end

      failed
    end

    private def import_context(clients : Hash(String, Zap::Client), context_file : String, reporter : Reporter) : Nil
      full_path = File.expand_path(context_file)
      clients.each do |api_host, zap_client|
        begin
          zap_client.context.import_context(full_path)
          reporter.info("context", "imported", api_host, full_path)
        rescue ex : Exception
          reporter.warn("context", "import failed #{format_error(ex)}", api_host, full_path)
        end
      end
    end

    private def with_zap_clients(api_hosts : Array(String), options : Options, &) : Nil
      clients = Hash(String, Zap::Client).new
      begin
        api_hosts.uniq.each do |host|
          clients[host] = Zap::Client.new(base_url: host, api_key: options.api_key)
        end
        yield clients
      ensure
        clients.each_value(&.close)
      end
    end

    private def execute_scan(zap_client : Zap::Client, scan_type : String, target : String, policy : String = "") : JSON::Any
      case scan_type
      when "spider"
        zap_client.spider.scan(url: target)
      when "active-scan"
        zap_client.ascan.scan(url: target, scan_policy_name: policy)
      when "ajax-spider"
        zap_client.ajax_spider.scan(url: target)
      else
        raise Zap::Error.new("Unknown scan type: #{scan_type}")
      end
    end

    private def extract_scan_id(result : JSON::Any) : String?
      data = result.as_h
      ["scan", "scanId", "scanid", "id"].each do |key|
        next unless value = data[key]?
        return stringify_json_value(value)
      end
      nil
    rescue TypeCastError | JSON::Error
      nil
    end

    private def stringify_json_value(value : JSON::Any) : String
      if string_value = value.as_s?
        string_value
      elsif int_value = value.as_i64?
        int_value.to_s
      elsif float_value = value.as_f?
        float_value.to_s
      elsif bool_value = value.as_bool?
        bool_value.to_s
      else
        value.to_s
      end
    end

    private def extract_status_string(result : JSON::Any) : String?
      value = result.as_h["status"]?
      return nil unless value
      stringify_json_value(value)
    rescue TypeCastError | JSON::Error
      nil
    end

    private def format_error(ex : Exception) : String
      if ex.is_a?(Zap::HttpError)
        "(HTTP #{ex.status_code})"
      elsif message = ex.message
        text = message.strip
        text.empty? ? "(transport error)" : "(#{text})"
      else
        "(unknown error)"
      end
    end

    private def normalize_api_hosts(apis : String) : Array(String)
      hosts = apis.split(",").map { |h| h.strip.rstrip('/') }.reject(&.empty?)
      if hosts.empty?
        raise ArgumentError.new("Please input --apis flag")
      end
      hosts
    end

    private def stop_all(apis : String, scan_type : String, options : Options, reporter : Reporter) : Nil
      success_count = 0
      failure_count = 0
      api_hosts = normalize_api_hosts(apis)

      with_zap_clients(api_hosts, options) do |clients|
        api_hosts.each do |api_host|
          zap_client = clients[api_host]
          begin
            case scan_type
            when "spider"
              zap_client.spider.stop_all
            when "active-scan"
              zap_client.ascan.stop_all
            when "ajax-spider"
              zap_client.ajax_spider.stop
            end
            success_count += 1
            reporter.info(scan_type, "stopped", api_host)
          rescue ex : Exception
            failure_count += 1
            reporter.warn(scan_type, "error (stop) #{format_error(ex)}", api_host)
          end
        end
      end

      reporter.info(scan_type, "summary success=#{success_count} failed=#{failure_count}")
    end

    private def wait_for_completion(
      scan_jobs : Array(ScanJob),
      ajax_wait_clients : Hash(String, Zap::Client),
      options : Options,
      reporter : Reporter = Reporter.new,
    ) : Nil
      pending_scan_jobs = scan_jobs.dup
      pending_ajax = ajax_wait_clients.to_a
      if pending_scan_jobs.empty? && pending_ajax.empty?
        return
      end

      reporter.info("wait", "start")
      started_at = Time.utc
      total_scan_jobs = pending_scan_jobs.size
      total_ajax_hosts = pending_ajax.size
      completed_scan_jobs = 0
      completed_ajax_hosts = 0
      poll_failures = 0
      timed_out = false
      last_poll_failure = {} of String => String

      loop do
        pending_scan_jobs.reject! do |job|
          completed, failed = poll_scan_job(job, reporter, last_poll_failure)
          completed_scan_jobs += 1 if completed
          poll_failures += 1 if failed
          completed
        end

        pending_ajax.reject! do |(api_host, zap_client)|
          completed, failed = poll_ajax_status(api_host, zap_client, reporter, last_poll_failure)
          completed_ajax_hosts += 1 if completed
          poll_failures += 1 if failed
          completed
        end

        break if pending_scan_jobs.empty? && pending_ajax.empty?

        if wait_timeout?(started_at, options.wait_timeout_seconds)
          timed_out = true
          pending_scan_jobs.each do |job|
            reporter.warn("wait", "timeout", job.api_host, "#{job.type}:#{job.target}")
          end
          pending_ajax.each do |(api_host, _)|
            reporter.warn("wait", "timeout", api_host, "ajax-spider")
          end
          break
        end

        sleep Math.max(options.wait_interval_seconds, 1).seconds
      end

      reporter.info("wait", "summary scan_completed=#{completed_scan_jobs}/#{total_scan_jobs} ajax_completed=#{completed_ajax_hosts}/#{total_ajax_hosts} poll_failures=#{poll_failures} timed_out=#{timed_out}")
    end

    private def poll_scan_job(
      job : ScanJob,
      reporter : Reporter,
      last_poll_failure : Hash(String, String),
    ) : {Bool, Bool}
      key = "#{job.api_host}|#{job.type}:#{job.target}"
      poll = check_scan_status(job)

      if poll.completed
        if reason = poll.failure_reason
          reporter.warn("wait", "completed with error #{reason}", job.api_host, "#{job.type}:#{job.target}")
        else
          reporter.info("wait", "complete", job.api_host, "#{job.type}:#{job.target}")
        end
        last_poll_failure.delete(key)
        {true, false}
      elsif reason = poll.failure_reason
        if last_poll_failure[key]? != reason
          reporter.warn("wait", "status check failed #{reason}", job.api_host, "#{job.type}:#{job.target}")
          last_poll_failure[key] = reason
        end
        {false, true}
      else
        {false, false}
      end
    end

    private def poll_ajax_status(
      api_host : String,
      zap_client : Zap::Client,
      reporter : Reporter,
      last_poll_failure : Hash(String, String),
    ) : {Bool, Bool}
      key = "#{api_host}|ajax-spider"

      begin
        result = zap_client.ajax_spider.status
        status = extract_status_string(result)
        if status.nil?
          reason = "(missing status value)"
          if last_poll_failure[key]? != reason
            reporter.warn("wait", "status check failed #{reason}", api_host, "ajax-spider")
            last_poll_failure[key] = reason
          end
          return {false, true}
        end

        if status_indicates_done?(status)
          if status_indicates_error?(status)
            reporter.warn("wait", "completed with error (scan ended with status: #{status.strip})", api_host, "ajax-spider")
          else
            reporter.info("wait", "complete", api_host, "ajax-spider")
          end
          last_poll_failure.delete(key)
          {true, false}
        else
          {false, false}
        end
      rescue ex : Exception
        reason = format_error(ex)
        if last_poll_failure[key]? != reason
          reporter.warn("wait", "status check failed #{reason}", api_host, "ajax-spider")
          last_poll_failure[key] = reason
        end
        {false, true}
      end
    end

    private def poll_pscan_status(
      api_host : String,
      zap_client : Zap::Client,
      reporter : Reporter,
      last_poll_failure : Hash(String, String),
    ) : {Bool, Bool}
      key = "#{api_host}|passive-scan"

      begin
        result = zap_client.pscan.records_to_scan
        records_value = result.as_h["recordsToScan"]?
        if records_value.nil?
          reason = "(missing recordsToScan value)"
          if last_poll_failure[key]? != reason
            reporter.warn("passive-scan", "status check failed #{reason}", api_host)
            last_poll_failure[key] = reason
          end
          return {false, true}
        end

        records_str = stringify_json_value(records_value)
        records = records_str.to_i?
        if records.nil?
          reason = "(invalid recordsToScan value: #{records_str})"
          if last_poll_failure[key]? != reason
            reporter.warn("passive-scan", "status check failed #{reason}", api_host)
            last_poll_failure[key] = reason
          end
          return {false, true}
        end

        if records <= 0
          reporter.info("passive-scan", "complete", api_host)
          last_poll_failure.delete(key)
          {true, false}
        else
          {false, false}
        end
      rescue ex : Exception
        reason = format_error(ex)
        if last_poll_failure[key]? != reason
          reporter.warn("passive-scan", "status check failed #{reason}", api_host)
          last_poll_failure[key] = reason
        end
        {false, true}
      end
    end

    private def check_scan_status(job : ScanJob) : WaitPollResult
      result = case job.type
               when "spider"
                 scan_id = job.scan_id.to_i? || -1
                 job.zap_client.spider.status(scan_id)
               when "active-scan"
                 scan_id = job.scan_id.to_i? || -1
                 job.zap_client.ascan.status(scan_id)
               else
                 return WaitPollResult.new(false, "(unknown scan type)")
               end

      status = extract_status_string(result)
      if status.nil?
        return WaitPollResult.new(false, "(missing status value)")
      end

      if status_indicates_done?(status)
        if status_indicates_error?(status)
          return WaitPollResult.new(true, "(scan ended with status: #{status.strip})")
        end
        return WaitPollResult.new(true, nil)
      end

      WaitPollResult.new(false, nil)
    rescue ex : Exception
      WaitPollResult.new(false, format_error(ex))
    end

    private def wait_timeout?(started_at : Time, timeout_seconds : Int32) : Bool
      return false if timeout_seconds <= 0
      (Time.utc - started_at).total_seconds >= timeout_seconds
    end

    private def status_indicates_done?(status : String) : Bool
      normalized = status.strip.downcase
      if percentage = normalized.to_i?
        return percentage >= 100
      end

      !RUNNING_STATUSES.includes?(normalized)
    end

    private def status_indicates_error?(status : String) : Bool
      normalized = status.strip.downcase
      ERROR_STATUSES.includes?(normalized)
    end

    private def generate_reports(report_targets_by_api : Hash(String, Set(String)), clients : Hash(String, Zap::Client), options : Options, reporter : Reporter) : Nil
      return if report_targets_by_api.empty?

      outputs = resolve_report_outputs(report_targets_by_api.keys, options)
      saved_count = 0
      fallback_count = 0
      failed_count = 0
      report_targets_by_api.each do |api_host, targets|
        output_path = outputs[api_host]
        next unless output_path
        zap_client = clients[api_host]

        filtered_ok, filtered_error = generate_filtered_report(zap_client, targets, output_path, options)
        if filtered_ok
          saved_count += 1
          reporter.info("report", "saved", api_host, output_path)
          next
        end

        reporter.warn("report", "filtered generation failed #{filtered_error}", api_host, output_path)
        core_ok, core_error = generate_core_report(zap_client, output_path, options)
        if core_ok
          fallback_count += 1
          reporter.warn("report", "generated without target filtering", api_host, output_path)
        else
          failed_count += 1
          reporter.warn("report", "error #{core_error}", api_host, output_path)
        end
      end
      reporter.info("report", "summary total=#{report_targets_by_api.size} saved=#{saved_count} fallback=#{fallback_count} failed=#{failed_count}")
    end

    private def resolve_report_outputs(api_hosts : Array(String), options : Options) : Hash(String, String)
      paths = {} of String => String
      return paths if api_hosts.empty?

      base_output = options.report_out
      if base_output.empty?
        base_output = "mzap-report-#{Time.utc.to_unix}.#{options.report_format}"
      end

      base_output, ext = normalize_report_output(base_output, options.report_format)

      if api_hosts.size == 1
        paths[api_hosts[0]] = base_output
        return paths
      end

      dir = File.dirname(base_output)
      stem = File.basename(base_output, ext)
      host_name_counts = Hash(String, Int32).new(0)
      api_hosts.each do |api_host|
        safe_host_base = sanitize_host(api_host)
        host_name_counts[safe_host_base] += 1
        suffix = host_name_counts[safe_host_base]
        safe_host = suffix == 1 ? safe_host_base : "#{safe_host_base}-#{suffix}"
        filename = "#{stem}-#{safe_host}#{ext}"
        if dir == "."
          paths[api_host] = filename
        else
          paths[api_host] = File.join(dir, filename)
        end
      end
      paths
    end

    private def normalize_report_output(base_output : String, report_format : String) : {String, String}
      expected_ext = ".#{report_format}"
      ext = File.extname(base_output)

      if ext.empty?
        return {"#{base_output}#{expected_ext}", expected_ext}
      end

      if ext.downcase == expected_ext
        return {base_output, ext}
      end

      dir = File.dirname(base_output)
      stem = File.basename(base_output, ext)
      normalized = if dir == "."
                     "#{stem}#{expected_ext}"
                   else
                     File.join(dir, "#{stem}#{expected_ext}")
                   end
      {normalized, expected_ext}
    end

    private def sanitize_host(value : String) : String
      normalized = value.gsub(/[^a-zA-Z0-9]+/, "-").lstrip('-').rstrip('-')
      normalized.empty? ? "host" : normalized
    end

    private def generate_filtered_report(
      zap_client : Zap::Client,
      targets : Set(String),
      output_path : String,
      options : Options,
    ) : {Bool, String}
      return {false, "(sarif uses alert-based generation)"} if options.report_format == "sarif"

      full_path = File.expand_path(output_path)
      report_dir = File.dirname(full_path)
      report_name = File.basename(full_path)
      Dir.mkdir_p(report_dir)

      template = report_template(options.report_format)
      zap_client.reports.generate(
        title: REPORT_TITLE,
        template: template,
        sites: targets.join("|"),
        report_file_name: report_name,
        report_dir: report_dir,
        display: false,
      )
      {true, ""}
    rescue ex : Exception
      {false, format_error(ex)}
    end

    private def generate_core_report(zap_client : Zap::Client, output_path : String, options : Options) : {Bool, String}
      full_path = File.expand_path(output_path)
      Dir.mkdir_p(File.dirname(full_path))

      case options.report_format
      when "html", "pdf"
        endpoint = options.report_format == "pdf" ? PDF_REPORT_API : HTML_REPORT_API
        body = zap_client.request_other(endpoint)
        File.write(full_path, body)
      when "json"
        alerts = zap_client.alert.alerts
        File.write(full_path, alerts.to_pretty_json)
      when "md"
        alerts_data = zap_client.alert.alerts
        markdown = generate_markdown_from_alerts(alerts_data)
        File.write(full_path, markdown)
      when "sarif"
        alerts_data = zap_client.alert.alerts
        sarif = generate_sarif_from_alerts(alerts_data)
        File.write(full_path, sarif)
      end
      {true, ""}
    rescue ex : Exception
      {false, format_error(ex)}
    end

    private def report_template(format : String) : String
      case format
      when "pdf"  then TEMPLATE_PDF
      when "json" then TEMPLATE_JSON
      when "md"   then TEMPLATE_MD
      else             TEMPLATE_HTML
      end
    end

    private def generate_sarif_from_alerts(alerts_data : JSON::Any) : String
      alerts = extract_alerts_array(alerts_data)
      log = Sarif::Builder.build do |b|
        b.run("ZAP", "2.x") do |r|
          rules_added = Set(String).new
          alerts.each do |alert|
            alert_hash = alert.as_h? || next
            plugin_id = alert_hash["pluginId"]?.try(&.as_s?) || alert_hash["id"]?.try { |v| stringify_json_value(v) } || "unknown"
            name = alert_hash["name"]?.try(&.as_s?) || alert_hash["alert"]?.try(&.as_s?) || "Unknown Alert"
            description = alert_hash["description"]?.try(&.as_s?) || ""
            uri = alert_hash["url"]?.try(&.as_s?) || alert_hash["uri"]?.try(&.as_s?) || ""
            risk_str = alert_hash["risk"]?.try(&.as_s?) || "Informational"

            unless rules_added.includes?(plugin_id)
              r.rule(plugin_id, name: name, short_description: description)
              rules_added << plugin_id
            end

            level = case risk_str.downcase
                    when "high"          then Sarif::Level::Error
                    when "medium"        then Sarif::Level::Warning
                    when "low", "info"   then Sarif::Level::Note
                    when "informational" then Sarif::Level::Note
                    else                      Sarif::Level::Warning
                    end

            message = alert_hash["alert"]?.try(&.as_s?) || name
            r.result(message, rule_id: plugin_id, level: level, uri: uri)
          end
        end
      end
      log.to_pretty_json
    end

    private def generate_markdown_from_alerts(alerts_data : JSON::Any) : String
      alerts = extract_alerts_array(alerts_data)
      io = IO::Memory.new
      io << "# ZAP Scan Report\n\n"
      io << "Generated by mzap\n\n"

      if alerts.empty?
        io << "No alerts found.\n"
        return io.to_s
      end

      io << "## Summary\n\n"
      io << "Total alerts: #{alerts.size}\n\n"
      io << "## Alerts\n\n"

      alerts.each_with_index do |alert, index|
        alert_hash = alert.as_h? || next
        name = alert_hash["name"]?.try(&.as_s?) || alert_hash["alert"]?.try(&.as_s?) || "Unknown Alert"
        risk = alert_hash["risk"]?.try(&.as_s?) || "Informational"
        confidence = alert_hash["confidence"]?.try(&.as_s?) || "Unknown"
        url = alert_hash["url"]?.try(&.as_s?) || alert_hash["uri"]?.try(&.as_s?) || ""
        description = alert_hash["description"]?.try(&.as_s?) || ""
        solution = alert_hash["solution"]?.try(&.as_s?) || ""

        io << "### #{index + 1}. #{name}\n\n"
        io << "- **Risk**: #{risk}\n"
        io << "- **Confidence**: #{confidence}\n"
        io << "- **URL**: #{url}\n" unless url.empty?
        io << "\n"
        io << "#{description}\n\n" unless description.empty?
        io << "**Solution**: #{solution}\n\n" unless solution.empty?
        io << "---\n\n"
      end

      io.to_s
    end

    private def extract_alerts_array(alerts_data : JSON::Any) : Array(JSON::Any)
      if arr = alerts_data.as_a?
        return arr
      end
      if hash = alerts_data.as_h?
        if alerts_arr = hash["alerts"]?.try(&.as_a?)
          return alerts_arr
        end
      end
      [] of JSON::Any
    end
  end
end
