require "zap"
require "set"

module Mzap
  # API-definition import concern for Mzap::Client: seeds ZAP's Sites Tree from
  # OpenAPI/SOAP/GraphQL/Postman definitions so the endpoints can be passively
  # scanned, reported, or actively scanned afterwards. Reuses the shared
  # passive-settle + report + fail-on tail from the rest of the client.
  module Client
    extend self

    OPENAPI_IMPORT_FILE_API = "/JSON/openapi/action/importFile/"
    OPENAPI_IMPORT_URL_API  = "/JSON/openapi/action/importUrl/"
    GRAPHQL_IMPORT_FILE_API = "/JSON/graphql/action/importFile/"
    GRAPHQL_IMPORT_URL_API  = "/JSON/graphql/action/importUrl/"
    SOAP_IMPORT_FILE_API    = "/JSON/soap/action/importFile/"
    SOAP_IMPORT_URL_API     = "/JSON/soap/action/importUrl/"
    POSTMAN_IMPORT_FILE_API = "/JSON/postman/action/importFile/"
    POSTMAN_IMPORT_URL_API  = "/JSON/postman/action/importUrl/"

    # Imports each spec from the `urls` list file (one location per line; a local
    # file path or an http(s):// URL) into every API host, round-robin. After
    # import, reuses the passive-settle + report + fail-on pipeline. Returns true
    # only when --fail-on is set and the gate is tripped.
    def import_api(urls : String, *, format : String, target_url : String = "", apis : String, options : Options, reporter : Reporter = Reporter.new) : Bool
      reporter.info("import", "start (#{format})")

      unless File.exists?(urls)
        reporter.warn("import", "spec list file not found", urls)
        return false
      end

      specs, duplicates_removed = read_targets(urls)
      if specs.empty? && duplicates_removed == 0
        reporter.warn("import", "no specs loaded from file", urls)
        return false
      end
      if duplicates_removed > 0
        reporter.warn("import", "removed #{duplicates_removed} duplicate spec(s)")
      end

      api_hosts = normalize_api_hosts(apis)
      with_zap_clients(api_hosts, options) do |clients|
        if !options.context.empty?
          import_context(clients, options.context, reporter)
        end

        success = 0
        errors = 0
        specs.each_with_index do |spec, index|
          api_host = api_hosts[index % api_hosts.size]
          zap_client = clients[api_host]
          begin
            with_retry(options.retry_count, options.retry_delay_seconds, reporter, "import", "import", api_host, spec) do
              dispatch_import(zap_client, format, spec, target_url)
            end
            success += 1
            reporter.info("import", "imported", api_host, spec)
          rescue ex : Exception
            errors += 1
            reporter.warn("import", "error #{format_error(ex)}", api_host, spec)
          end
        end

        reporter.info("import", "summary specs=#{specs.size} success=#{success} errors=#{errors}")

        if options.wait_enabled?
          wait_for_passive_scan(api_hosts, clients, options, reporter)
          print_alert_summary(clients, reporter)
        end

        if options.report_enabled?
          report_targets = Hash(String, Set(String)).new { |hash, key| hash[key] = Set(String).new }
          api_hosts.uniq.each { |host| report_targets[host] = Set(String).new }
          generate_reports(report_targets, clients, options, reporter)
        end

        if !options.fail_on.empty?
          return check_fail_on(clients, options, reporter)
        end
      end
      false
    end

    # Routes a single spec to the right ZAP import endpoint based on `format` and
    # whether the spec is a URL or a local file. `target_url` overrides the
    # imported target (OpenAPI target/host override; GraphQL endpoint).
    private def dispatch_import(zap_client : Zap::Client, format : String, spec : String, target_url : String) : JSON::Any
      is_url = spec.starts_with?("http://") || spec.starts_with?("https://")
      case format
      when "openapi"
        is_url ? zap_client.openapi.import_url(spec, host_override: target_url) : zap_client.openapi.import_file(spec, target: target_url)
      when "graphql"
        is_url ? zap_client.graphql.import_url(spec, endpoint: target_url) : zap_client.graphql.import_file(spec, endpoint: target_url)
      when "soap"
        is_url ? zap_client.soap.import_url(spec) : zap_client.soap.import_file(spec)
      when "postman"
        is_url ? zap_client.postman.import_url(spec) : zap_client.postman.import_file(spec)
      else
        raise Zap::Error.new("Unknown import format: #{format}")
      end
    end
  end
end
