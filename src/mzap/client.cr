require "http/client"
require "http/params"
require "json"
require "set"
require "uri"

module Mzap
  module Client
    extend self

    ACCESS_API      = "/JSON/core/action/accessUrl"
    SPIDER_API      = "/JSON/spider/action/scan/"
    ASCAN_API       = "/JSON/ascan/action/scan/"
    AJAX_SPIDER_API = "/JSON/ajaxSpider/action/scan/"
    SPIDER_STATUS   = "/JSON/spider/view/status/"
    ASCAN_STATUS    = "/JSON/ascan/view/status/"
    AJAX_STATUS     = "/JSON/ajaxSpider/view/status/"

    ASCAN_STOP       = "/JSON/ascan/action/stopAllScans/?"
    SPIDER_STOP      = "/JSON/spider/action/stopAllScans/?"
    AJAX_SPIDER_STOP = "/JSON/ajaxSpider/action/stop/"

    REPORT_GENERATE_API = "/JSON/reports/action/generate/"
    HTML_REPORT_API     = "/OTHER/core/other/htmlreport/"
    PDF_REPORT_API      = "/OTHER/core/other/pdfreport/"

    REPORT_TITLE  = "mzap report"
    TEMPLATE_HTML = "traditional-html"
    TEMPLATE_PDF  = "traditional-pdf"

    RUNNING_STATUSES = {"running", "inprogress", "in_progress", "started", "busy"}
    ERROR_STATUSES   = {"error", "failed", "failure", "aborted"}

    private record ApiCallResult, success : Bool, body : String, status_code : Int32?, error_message : String?
    private record ScanJob, type : String, api_host : String, target : String, scan_id : String, status_api : String
    private record WaitPollResult, completed : Bool, failure_reason : String?

    def spider(urls : String, apis : String, options : Options, reporter : Reporter = Reporter.new) : Nil
      run(urls, apis, SPIDER_API, options, reporter)
    end

    def ajax_spider(urls : String, apis : String, options : Options, reporter : Reporter = Reporter.new) : Nil
      run(urls, apis, AJAX_SPIDER_API, options, reporter)
    end

    def active_scan(urls : String, apis : String, options : Options, reporter : Reporter = Reporter.new) : Nil
      run(urls, apis, ASCAN_API, options, reporter)
    end

    def stop_spider(apis : String, options : Options, reporter : Reporter = Reporter.new) : Nil
      stop_all(apis, SPIDER_STOP, options, reporter)
    end

    def stop_active_scan(apis : String, options : Options, reporter : Reporter = Reporter.new) : Nil
      stop_all(apis, ASCAN_STOP, options, reporter)
    end

    def stop_ajax_spider(apis : String, options : Options, reporter : Reporter = Reporter.new) : Nil
      stop_all(apis, AJAX_SPIDER_STOP, options, reporter)
    end

    def run(urls : String, apis : String, prefix : String, options : Options, reporter : Reporter = Reporter.new) : Nil
      scan_type = scan_type_for(prefix)
      reporter.info(scan_type, "start")

      unless File.exists?(urls)
        reporter.warn(scan_type, "target file not found", urls)
        return
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
        return
      end

      if duplicates_removed > 0
        reporter.warn(scan_type, "removed #{duplicates_removed} duplicate target(s)")
      end

      api_hosts = normalize_api_hosts(apis)
      index = 0
      scan_jobs = [] of ScanJob
      ajax_wait_hosts = Set(String).new
      report_targets_by_api = Hash(String, Set(String)).new { |hash, key| hash[key] = Set(String).new }
      access_errors = 0
      scan_errors = 0
      scan_success = 0

      targets.each do |target|
        api_host = api_hosts[index]

        access_result = call_scan_api(target, api_host, ACCESS_API, options)
        unless access_result.success
          access_errors += 1
          reporter.warn(scan_type, "error (access) #{api_call_failure_reason(access_result)}", api_host, target)
        end

        scan_result = call_scan_api(target, api_host, prefix, options)
        if !scan_result.success
          scan_errors += 1
          reporter.warn(scan_type, "error (scan) #{api_call_failure_reason(scan_result)}", api_host, target)
        else
          scan_success += 1
          report_targets_by_api[api_host] << target
          reporter.info(scan_type, "added", api_host, target)
          if options.wait_enabled?
            case prefix
            when SPIDER_API
              register_scan_job(scan_jobs, scan_result.body, scan_type, api_host, target, SPIDER_STATUS, reporter)
            when ASCAN_API
              register_scan_job(scan_jobs, scan_result.body, scan_type, api_host, target, ASCAN_STATUS, reporter)
            when AJAX_SPIDER_API
              ajax_wait_hosts.add(api_host)
            end
          end
        end

        index = (index + 1) % api_hosts.size
      end

      reporter.info(scan_type, "summary targets=#{targets.size} success=#{scan_success} scan_errors=#{scan_errors} access_errors=#{access_errors}")

      if options.wait_enabled?
        wait_for_completion(scan_jobs, ajax_wait_hosts, options, reporter)
      end

      if options.report_enabled?
        generate_reports(report_targets_by_api, options, reporter)
      end
    end

    def stop(api : String, prefix : String, options : Options, reporter : Reporter = Reporter.new) : Bool
      uri = URI.parse("#{api}#{prefix}")
      result = get_response(uri, options)

      if result.success
        reporter.info(prefix, "stopped", api)
        true
      else
        reporter.warn(prefix, "error (stop) #{api_call_failure_reason(result)}", api)
        false
      end
    end

    private def scan_type_for(prefix : String) : String
      case prefix
      when SPIDER_API
        "spider"
      when ASCAN_API
        "active-scan"
      when AJAX_SPIDER_API
        "ajax-spider"
      else
        "scan"
      end
    end

    private def call_scan_api(target : String, api_host : String, prefix : String, options : Options) : ApiCallResult
      uri = build_target_uri(target, api_host, prefix)
      get_response(uri, options)
    end

    private def normalize_api_hosts(apis : String) : Array(String)
      hosts = apis.split(",").map { |h| h.strip.gsub(/\/+$/, "") }.reject(&.empty?)
      if hosts.empty?
        raise ArgumentError.new("Please input --apis flag")
      end
      hosts
    end

    private def build_target_uri(target : String, api_host : String, prefix : String) : URI
      uri = URI.parse("#{api_host}#{prefix}")
      query = HTTP::Params.parse(uri.query || "")
      query["url"] = target
      uri.query = query.to_s
      uri
    end

    private def get_response(uri : URI, options : Options) : ApiCallResult
      success = false
      body = ""
      status_code : Int32? = nil
      HTTP::Client.get(uri, headers: options.headers) do |response|
        success = response.success?
        status_code = response.status_code
        body = drain_response(response)
      end
      ApiCallResult.new(success, body, status_code, nil)
    rescue ex : Exception # Network errors (Socket::Error, IO::Error, etc.) vary widely
      ApiCallResult.new(false, "", nil, ex.message || ex.class.name)
    end

    private def stop_all(apis : String, prefix : String, options : Options, reporter : Reporter) : Nil
      success_count = 0
      failure_count = 0
      normalize_api_hosts(apis).each do |api|
        if stop(api, prefix, options, reporter)
          success_count += 1
        else
          failure_count += 1
        end
      end
      reporter.info(prefix, "summary success=#{success_count} failed=#{failure_count}")
    end

    private def api_call_failure_reason(result : ApiCallResult) : String
      if status_code = result.status_code
        return "(HTTP #{status_code})"
      end

      if error_message = result.error_message
        text = error_message.strip
        return text.empty? ? "(transport error)" : "(#{text})"
      end

      "(unknown error)"
    end

    private def drain_response(response : HTTP::Client::Response) : String
      if body_io = response.body_io
        body_io.gets_to_end
      else
        ""
      end
    end

    private def register_scan_job(
      scan_jobs : Array(ScanJob),
      response_body : String,
      scan_type : String,
      api_host : String,
      target : String,
      status_api : String,
      reporter : Reporter,
    ) : Nil
      scan_id = parse_scan_id(response_body)
      if scan_id
        scan_jobs << ScanJob.new(scan_type, api_host, target, scan_id, status_api)
      else
        reporter.warn(scan_type, "missing scan id (wait disabled for target)", api_host, target)
      end
    end

    private def parse_scan_id(body : String) : String?
      extract_json_value(body, ["scan", "scanId", "scanid", "id"])
    end

    private def parse_status(body : String) : String?
      extract_json_value(body, ["status"])
    end

    private def extract_json_value(body : String, keys : Array(String)) : String?
      begin
        data = JSON.parse(body).as_h
      rescue ex : JSON::ParseException
        return nil
      end

      keys.each do |key|
        next unless value = data[key]?
        return stringify_json_value(value)
      end
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

    private def wait_for_completion(
      scan_jobs : Array(ScanJob),
      ajax_wait_hosts : Set(String),
      options : Options,
      reporter : Reporter = Reporter.new,
    ) : Nil
      pending_scan_jobs = scan_jobs.dup
      pending_ajax_hosts = ajax_wait_hosts.to_a
      if pending_scan_jobs.empty? && pending_ajax_hosts.empty?
        return
      end

      reporter.info("wait", "start")
      started_at = Time.utc
      total_scan_jobs = pending_scan_jobs.size
      total_ajax_hosts = pending_ajax_hosts.size
      completed_scan_jobs = 0
      completed_ajax_hosts = 0
      poll_failures = 0
      timed_out = false
      last_poll_failure = {} of String => String

      loop do
        pending_scan_jobs.reject! do |job|
          completed, failed = poll_job_status(job.api_host, job.status_api, job.scan_id, "#{job.type}:#{job.target}", options, reporter, last_poll_failure)
          completed_scan_jobs += 1 if completed
          poll_failures += 1 if failed
          completed
        end

        pending_ajax_hosts.reject! do |api_host|
          completed, failed = poll_job_status(api_host, AJAX_STATUS, nil, "ajax-spider", options, reporter, last_poll_failure)
          completed_ajax_hosts += 1 if completed
          poll_failures += 1 if failed
          completed
        end

        break if pending_scan_jobs.empty? && pending_ajax_hosts.empty?

        if wait_timeout?(started_at, options.wait_timeout_seconds)
          timed_out = true
          pending_scan_jobs.each do |job|
            reporter.warn("wait", "timeout", job.api_host, "#{job.type}:#{job.target}")
          end
          pending_ajax_hosts.each do |api_host|
            reporter.warn("wait", "timeout", api_host, "ajax-spider")
          end
          break
        end

        sleep options.wait_interval_seconds.seconds
      end

      reporter.info("wait", "summary scan_completed=#{completed_scan_jobs}/#{total_scan_jobs} ajax_completed=#{completed_ajax_hosts}/#{total_ajax_hosts} poll_failures=#{poll_failures} timed_out=#{timed_out}")
    end

    private def poll_job_status(
      api_host : String,
      status_api : String,
      scan_id : String?,
      job_name : String,
      options : Options,
      reporter : Reporter,
      last_poll_failure : Hash(String, String),
    ) : {Bool, Bool}
      poll = check_scan_status(api_host, status_api, scan_id, options)
      key = "#{api_host}|#{job_name}"
      if poll.completed
        if reason = poll.failure_reason
          reporter.warn("wait", "completed with error #{reason}", api_host, job_name)
        else
          reporter.info("wait", "complete", api_host, job_name)
        end
        last_poll_failure.delete(key)
        {true, false}
      elsif reason = poll.failure_reason
        if last_poll_failure[key]? != reason
          reporter.warn("wait", "status check failed #{reason}", api_host, job_name)
          last_poll_failure[key] = reason
        end
        {false, true}
      else
        {false, false}
      end
    end

    private def wait_timeout?(started_at : Time, timeout_seconds : Int32) : Bool
      return false if timeout_seconds <= 0
      (Time.utc - started_at).total_seconds >= timeout_seconds
    end

    private def check_scan_status(api_host : String, status_api : String, scan_id : String?, options : Options) : WaitPollResult
      uri = URI.parse("#{api_host}#{status_api}")
      if scan_id
        query = HTTP::Params.parse(uri.query || "")
        query["scanId"] = scan_id
        uri.query = query.to_s
      end

      result = get_response(uri, options)
      unless result.success
        return WaitPollResult.new(false, api_call_failure_reason(result))
      end
      status = parse_status(result.body)
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

    private def generate_reports(report_targets_by_api : Hash(String, Set(String)), options : Options, reporter : Reporter) : Nil
      return if report_targets_by_api.empty?

      outputs = resolve_report_outputs(report_targets_by_api.keys, options)
      saved_count = 0
      fallback_count = 0
      failed_count = 0
      report_targets_by_api.each do |api_host, targets|
        output_path = outputs[api_host]
        next unless output_path

        filtered_result = generate_filtered_report(api_host, targets, output_path, options)
        if filtered_result.success
          saved_count += 1
          reporter.info("report", "saved", api_host, output_path)
          next
        end

        reporter.warn("report", "filtered generation failed #{api_call_failure_reason(filtered_result)}", api_host, output_path)
        core_result = generate_core_report(api_host, output_path, options)
        if core_result.success
          fallback_count += 1
          reporter.warn("report", "generated without target filtering", api_host, output_path)
        else
          failed_count += 1
          reporter.warn("report", "error #{api_call_failure_reason(core_result)}", api_host, output_path)
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
      normalized = value.gsub(/[^a-zA-Z0-9]+/, "-").gsub(/^-+/, "").gsub(/-+$/, "")
      normalized.empty? ? "host" : normalized
    end

    private def generate_filtered_report(
      api_host : String,
      targets : Set(String),
      output_path : String,
      options : Options,
    ) : ApiCallResult
      full_path = File.expand_path(output_path)
      report_dir = File.dirname(full_path)
      report_name = File.basename(full_path)
      Dir.mkdir_p(report_dir)

      uri = URI.parse("#{api_host}#{REPORT_GENERATE_API}")
      query = HTTP::Params.parse(uri.query || "")
      query["template"] = options.report_format == "pdf" ? TEMPLATE_PDF : TEMPLATE_HTML
      query["title"] = REPORT_TITLE
      query["sites"] = targets.join("|")
      query["reportFileName"] = report_name
      query["reportDir"] = report_dir
      query["display"] = "false"
      uri.query = query.to_s

      get_response(uri, options)
    rescue ex : File::Error | IO::Error
      ApiCallResult.new(false, "", nil, ex.message || ex.class.name)
    end

    private def generate_core_report(api_host : String, output_path : String, options : Options) : ApiCallResult
      endpoint = options.report_format == "pdf" ? PDF_REPORT_API : HTML_REPORT_API
      uri = URI.parse("#{api_host}#{endpoint}")
      result = get_response(uri, options)
      return result unless result.success

      full_path = File.expand_path(output_path)
      Dir.mkdir_p(File.dirname(full_path))
      File.write(full_path, result.body)
      ApiCallResult.new(true, result.body, result.status_code, nil)
    rescue ex : File::Error | IO::Error
      ApiCallResult.new(false, "", nil, ex.message || ex.class.name)
    end
  end
end
