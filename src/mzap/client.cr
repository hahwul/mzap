require "zap"
require "sarif"
require "set"

module Mzap
  module Client
    extend self

    ACCESS_API         = "/JSON/core/action/accessUrl/"
    SPIDER_API         = "/JSON/spider/action/scan/"
    ASCAN_API          = "/JSON/ascan/action/scan/"
    AJAX_SPIDER_API    = "/JSON/ajaxSpider/action/scan/"
    CLIENT_SPIDER_API  = "/JSON/clientSpider/action/scan/"
    SPIDER_STATUS      = "/JSON/spider/view/status/"
    ASCAN_STATUS       = "/JSON/ascan/view/status/"
    AJAX_STATUS        = "/JSON/ajaxSpider/view/status/"
    CLIENT_SPIDER_STAT = "/JSON/clientSpider/view/status/"

    PSCAN_RECORDS_TO_SCAN = "/JSON/pscan/view/recordsToScan/"

    SPIDER_STOP        = "/JSON/spider/action/stopAllScans/"
    ASCAN_STOP         = "/JSON/ascan/action/stopAllScans/"
    AJAX_SPIDER_STOP   = "/JSON/ajaxSpider/action/stop/"
    CLIENT_SPIDER_STOP = "/JSON/clientSpider/action/stop/"

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
    # Outcome of a single status poll: whether the job finished, and whether this
    # poll attempt itself failed (so callers can count failures without guessing
    # which element of an anonymous tuple means what).
    private record PollOutcome, completed : Bool, poll_failed : Bool
    # Outcome of a report write attempt: success flag plus a human-readable error
    # message (empty when ok).
    private record ReportOutcome, ok : Bool, error : String

    def spider(urls : String, *, apis : String, options : Options, reporter : Reporter = Reporter.new) : Bool
      run(urls, apis, "spider", options, reporter)
    end

    def ajax_spider(urls : String, *, apis : String, options : Options, reporter : Reporter = Reporter.new) : Bool
      run(urls, apis, "ajax-spider", options, reporter)
    end

    def active_scan(urls : String, *, apis : String, options : Options, reporter : Reporter = Reporter.new) : Bool
      run(urls, apis, "active-scan", options, reporter)
    end

    # Client Spider is the modern, browser-based crawler introduced in ZAP 2.16
    # (the "client" add-on). Requires ZAP >= 2.16 with the Client Side Integration
    # add-on installed; otherwise the scan dispatch surfaces a clear API error.
    def client_spider(urls : String, *, apis : String, options : Options, reporter : Reporter = Reporter.new) : Bool
      run(urls, apis, "client-spider", options, reporter)
    end

    def passive_scan(apis : String, *, options : Options, reporter : Reporter = Reporter.new) : Bool
      reporter.info("passive-scan", "start")

      api_hosts = normalize_api_hosts(apis)
      with_zap_clients(api_hosts, options) do |clients|
        wait_for_passive_scan(api_hosts, clients, options, reporter)

        print_alert_summary(clients, reporter)

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

    def stop_client_spider(apis : String, *, options : Options, reporter : Reporter = Reporter.new) : Nil
      stop_all(apis, "client-spider", options, reporter)
    end

    def run(urls : String, apis : String, scan_type : String, options : Options, reporter : Reporter = Reporter.new) : Bool
      reporter.info(scan_type, "start")

      unless File.exists?(urls)
        reporter.warn(scan_type, "target file not found", urls)
        return false
      end

      targets, duplicates_removed = read_targets(urls)

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
        access_errors, scan_errors, scan_success = execute_dispatch(
          targets, api_hosts, clients, scan_type, options,
          scan_jobs, ajax_wait_clients, report_targets_by_api, reporter,
        )

        reporter.info(scan_type, "summary targets=#{targets.size} success=#{scan_success} scan_errors=#{scan_errors} access_errors=#{access_errors}")

        if options.wait_enabled?
          wait_for_completion(scan_jobs, ajax_wait_clients, options, reporter)
          print_alert_summary(clients, reporter)
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

    # Distributes targets across API hosts (round-robin) and dispatches each one,
    # either sequentially or across a bounded pool of fibers when --concurrency > 1.
    # Shared accumulators (scan_jobs, ajax_wait_clients, report_targets_by_api) are
    # mutated in place; returns the aggregated {access_errors, scan_errors, scan_success}.
    private def execute_dispatch(
      targets : Array(String),
      api_hosts : Array(String),
      clients : Hash(String, Zap::Client),
      scan_type : String,
      options : Options,
      scan_jobs : Array(ScanJob),
      ajax_wait_clients : Hash(String, Zap::Client),
      report_targets_by_api : Hash(String, Set(String)),
      reporter : Reporter,
    ) : {Int32, Int32, Int32}
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
            begin
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
              end
            rescue ex : Exception
              reporter.warn(scan_type, "fiber dispatch failed: #{ex.message || ex.to_s}", api_host, target)
              mutex.synchronize do
                scan_errors += 1
              end
            ensure
              semaphore.send(nil)
              done.send(nil)
            end
          end
        end

        dispatch_targets.size.times { done.receive }
      end

      {access_errors, scan_errors, scan_success}
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
        with_retry(options.retry_count, options.retry_delay_seconds, reporter, scan_type, "access", api_host, target) do
          zap_client.core.access_url(target)
        end
      rescue ex : Exception
        access_errors = 1
        reporter.warn(scan_type, "error (access) #{format_error(ex)}", api_host, target)
      end

      begin
        result = with_retry(options.retry_count, options.retry_delay_seconds, reporter, scan_type, "scan", api_host, target) do
          execute_scan(zap_client, scan_type, target, options.policy)
        end
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
      when "spider", "active-scan", "client-spider"
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

    private def with_retry(max_retries : Int32, delay_seconds : Int32, reporter : Reporter, scan_type : String, operation : String, api_host : String, target : String, &)
      attempt = 0
      loop do
        begin
          return yield
        rescue ex : Exception
          attempt += 1
          if attempt > max_retries
            raise ex
          end
          reporter.warn(scan_type, "#{operation} failed #{format_error(ex)}, retry #{attempt}/#{max_retries}", api_host, target)
          sleep delay_seconds.seconds if delay_seconds > 0
        end
      end
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
      when "client-spider"
        zap_client.client_spider.scan(url: target)
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

    # Reads a target/spec list file, stripping blanks and `#` comments and removing
    # duplicates while preserving order. Returns the unique entries plus the count
    # of duplicates dropped, so callers can warn appropriately.
    private def read_targets(path : String) : {Array(String), Int32}
      targets = [] of String
      seen = Set(String).new
      duplicates_removed = 0
      File.each_line(path) do |line|
        value = line.strip
        next if value.empty?
        next if value.starts_with?('#')
        if seen.add?(value)
          targets << value
        else
          duplicates_removed += 1
        end
      end
      {targets, duplicates_removed}
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
            when "client-spider"
              zap_client.client_spider.stop
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
  end
end

require "./client/alerts"
require "./client/wait"
require "./client/reports"
require "./client/imports"
require "./client/inspect"
