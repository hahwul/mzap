require "http/client"
require "http/params"
require "json"
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

    private record ApiCallResult, success : Bool, body : String
    private record ScanJob, type : String, api_host : String, target : String, scan_id : String, status_api : String

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
      normalize_api_hosts(apis).each do |api|
        stop(api, SPIDER_STOP, options, reporter)
      end
    end

    def stop_active_scan(apis : String, options : Options, reporter : Reporter = Reporter.new) : Nil
      normalize_api_hosts(apis).each do |api|
        stop(api, ASCAN_STOP, options, reporter)
      end
    end

    def stop_ajax_spider(apis : String, options : Options, reporter : Reporter = Reporter.new) : Nil
      normalize_api_hosts(apis).each do |api|
        stop(api, AJAX_SPIDER_STOP, options, reporter)
      end
    end

    def run(urls : String, apis : String, prefix : String, options : Options, reporter : Reporter = Reporter.new) : Nil
      scan_type = scan_type_for(prefix)
      reporter.info(scan_type, "start")

      targets = [] of String
      File.each_line(urls) do |line|
        value = line.strip
        next if value.empty?
        next if value.starts_with?('#')
        targets << value
      end

      if targets.empty?
        reporter.warn(scan_type, "no targets loaded from file", urls)
        return
      end

      api_hosts = normalize_api_hosts(apis)
      index = 0
      scan_jobs = [] of ScanJob
      ajax_wait_hosts = [] of String
      report_targets_by_api = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }

      targets.each do |target|
        api_host = api_hosts[index]
        unless report_targets_by_api[api_host].includes?(target)
          report_targets_by_api[api_host] << target
        end

        if call_api(target, api_host, ACCESS_API, options)
          reporter.warn(scan_type, "error (access)", api_host, target)
        end

        scan_result = call_scan_api(target, api_host, prefix, options)
        if !scan_result.success
          reporter.warn(scan_type, "error (scan)", api_host, target)
        else
          reporter.info(scan_type, "added", api_host, target)
          if options.wait_enabled?
            case prefix
            when SPIDER_API
              register_scan_job(scan_jobs, scan_result.body, scan_type, api_host, target, SPIDER_STATUS, reporter)
            when ASCAN_API
              register_scan_job(scan_jobs, scan_result.body, scan_type, api_host, target, ASCAN_STATUS, reporter)
            when AJAX_SPIDER_API
              ajax_wait_hosts << api_host unless ajax_wait_hosts.includes?(api_host)
            end
          end
        end

        if api_hosts.size - 1 > index
          index += 1
        else
          index = 0
        end
      end

      if options.wait_enabled?
        wait_for_completion(scan_jobs, ajax_wait_hosts, options, reporter)
      end

      if options.report_enabled?
        generate_reports(report_targets_by_api, options, reporter)
      end
    end

    def stop(api : String, prefix : String, options : Options, reporter : Reporter = Reporter.new) : Nil
      success = false
      begin
        HTTP::Client.get("#{api}#{prefix}", headers: request_headers(options)) do |response|
          success = response.success?
          drain_response(response)
        end
      rescue
        success = false
      end

      if success
        reporter.info(prefix, "stopped", api)
      else
        reporter.warn(prefix, "error (stop)", api)
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

    private def call_api(target : String, api_host : String, prefix : String, options : Options) : Bool
      result = call_scan_api(target, api_host, prefix, options)
      !result.success
    end

    private def call_scan_api(target : String, api_host : String, prefix : String, options : Options) : ApiCallResult
      uri = build_target_uri(target, api_host, prefix)
      get_response(uri, options)
    end

    private def normalize_api_hosts(apis : String) : Array(String)
      hosts = apis.split(",").map(&.strip).reject(&.empty?)
      if hosts.empty?
        raise ArgumentError.new("Please input --apis flag")
      end
      hosts
    end

    private def request_headers(options : Options) : HTTP::Headers
      headers = HTTP::Headers.new
      unless options.api_key.empty?
        headers["X-ZAP-API-Key"] = options.api_key
      end
      headers
    end

    private def build_target_uri(target : String, api_host : String, prefix : String) : URI
      uri = URI.parse("#{api_host}#{prefix}")
      query = HTTP::Params.parse(uri.query || "")
      query["url"] = target
      uri.query = query.to_s
      uri
    end

    private def get_response(uri : URI, options : Options) : ApiCallResult
      begin
        success = false
        body = ""
        HTTP::Client.get(uri, headers: request_headers(options)) do |response|
          success = response.success?
          body = drain_response(response)
        end
        ApiCallResult.new(success, body)
      rescue
        ApiCallResult.new(false, "")
      end
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
      rescue
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
      ajax_wait_hosts : Array(String),
      options : Options,
      reporter : Reporter = Reporter.new,
    ) : Nil
      pending_scan_jobs = scan_jobs.dup
      pending_ajax_hosts = ajax_wait_hosts.dup
      if pending_scan_jobs.empty? && pending_ajax_hosts.empty?
        return
      end

      reporter.info("wait", "start")
      started_at = Time.utc

      loop do
        pending_scan_jobs.reject! do |job|
          if scan_job_completed?(job, options)
            reporter.info("wait", "complete", job.api_host, "#{job.type}:#{job.target}")
            true
          else
            false
          end
        end

        pending_ajax_hosts.reject! do |api_host|
          if ajax_scan_completed?(api_host, options)
            reporter.info("wait", "complete", api_host, "ajax-spider")
            true
          else
            false
          end
        end

        break if pending_scan_jobs.empty? && pending_ajax_hosts.empty?

        if wait_timeout?(started_at, options.wait_timeout_seconds)
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
    end

    private def wait_timeout?(started_at : Time, timeout_seconds : Int32) : Bool
      return false if timeout_seconds <= 0
      (Time.utc - started_at).total_seconds >= timeout_seconds
    end

    private def scan_job_completed?(job : ScanJob, options : Options) : Bool
      uri = URI.parse("#{job.api_host}#{job.status_api}")
      query = HTTP::Params.parse(uri.query || "")
      query["scanId"] = job.scan_id
      uri.query = query.to_s

      result = get_response(uri, options)
      return false unless result.success
      status = parse_status(result.body)
      status_indicates_done?(status)
    end

    private def ajax_scan_completed?(api_host : String, options : Options) : Bool
      uri = URI.parse("#{api_host}#{AJAX_STATUS}")
      result = get_response(uri, options)
      return false unless result.success
      status = parse_status(result.body)
      status_indicates_done?(status)
    end

    private def status_indicates_done?(status : String?) : Bool
      return false unless status

      normalized = status.not_nil!.strip.downcase
      if percentage = normalized.to_i?
        return percentage >= 100
      end

      !{"running", "inprogress", "in_progress", "started", "busy"}.includes?(normalized)
    end

    private def generate_reports(report_targets_by_api : Hash(String, Array(String)), options : Options, reporter : Reporter) : Nil
      return if report_targets_by_api.empty?

      outputs = resolve_report_outputs(report_targets_by_api.keys, options)
      report_targets_by_api.each do |api_host, targets|
        output_path = outputs[api_host]
        next unless output_path

        if generate_filtered_report(api_host, targets, output_path, options)
          reporter.info("report", "saved", api_host, output_path)
          next
        end

        if generate_core_report(api_host, output_path, options)
          reporter.warn("report", "generated without target filtering", api_host, output_path)
        else
          reporter.warn("report", "error", api_host, output_path)
        end
      end
    end

    private def resolve_report_outputs(api_hosts : Array(String), options : Options) : Hash(String, String)
      paths = {} of String => String
      return paths if api_hosts.empty?

      base_output = options.report_out
      if base_output.empty?
        base_output = "mzap-report-#{Time.utc.to_unix}.#{options.report_format}"
      end

      expected_ext = ".#{options.report_format}"
      ext = File.extname(base_output)
      if ext.empty?
        base_output = "#{base_output}#{expected_ext}"
        ext = expected_ext
      end

      if api_hosts.size == 1
        paths[api_hosts[0]] = base_output
        return paths
      end

      dir = File.dirname(base_output)
      stem = File.basename(base_output, ext)
      api_hosts.each do |api_host|
        safe_host = sanitize_host(api_host)
        filename = "#{stem}-#{safe_host}#{ext}"
        if dir == "."
          paths[api_host] = filename
        else
          paths[api_host] = File.join(dir, filename)
        end
      end
      paths
    end

    private def sanitize_host(value : String) : String
      normalized = value.gsub(/[^a-zA-Z0-9]+/, "-").gsub(/^-+/, "").gsub(/-+$/, "")
      normalized.empty? ? "host" : normalized
    end

    private def generate_filtered_report(
      api_host : String,
      targets : Array(String),
      output_path : String,
      options : Options,
    ) : Bool
      full_path = File.expand_path(output_path)
      report_dir = File.dirname(full_path)
      report_name = File.basename(full_path)
      Dir.mkdir_p(report_dir)

      uri = URI.parse("#{api_host}#{REPORT_GENERATE_API}")
      query = HTTP::Params.parse(uri.query || "")
      query["template"] = options.report_format == "pdf" ? "traditional-pdf" : "traditional-html"
      query["title"] = "mzap report"
      query["sites"] = targets.join("|")
      query["reportFileName"] = report_name
      query["reportDir"] = report_dir
      query["display"] = "false"
      uri.query = query.to_s

      result = get_response(uri, options)
      result.success
    rescue
      false
    end

    private def generate_core_report(api_host : String, output_path : String, options : Options) : Bool
      endpoint = options.report_format == "pdf" ? PDF_REPORT_API : HTML_REPORT_API
      uri = URI.parse("#{api_host}#{endpoint}")
      result = get_response(uri, options)
      return false unless result.success

      full_path = File.expand_path(output_path)
      Dir.mkdir_p(File.dirname(full_path))
      File.write(full_path, result.body)
      true
    rescue
      false
    end
  end
end
