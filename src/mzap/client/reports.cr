require "zap"
require "sarif"
require "set"

module Mzap
  # Report concern for Mzap::Client: resolves per-host output paths and renders
  # scan results, preferring ZAP's filtered report add-on and falling back to the
  # core report endpoints or locally generated json/md/sarif output.
  module Client
    extend self

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

        filtered = generate_filtered_report(zap_client, targets, output_path, options)
        if filtered.ok
          saved_count += 1
          reporter.info("report", "saved", api_host, output_path)
          next
        end

        reporter.warn("report", "filtered generation failed #{filtered.error}", api_host, output_path)
        core = generate_core_report(zap_client, output_path, options)
        if core.ok
          fallback_count += 1
          reporter.warn("report", "generated without target filtering", api_host, output_path)
        else
          failed_count += 1
          reporter.warn("report", "error #{core.error}", api_host, output_path)
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
    ) : ReportOutcome
      return ReportOutcome.new(ok: false, error: "(sarif uses alert-based generation)") if options.report_format == "sarif"

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
      ReportOutcome.new(ok: true, error: "")
    rescue ex : Exception
      ReportOutcome.new(ok: false, error: format_error(ex))
    end

    private def generate_core_report(zap_client : Zap::Client, output_path : String, options : Options) : ReportOutcome
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
      ReportOutcome.new(ok: true, error: "")
    rescue ex : Exception
      ReportOutcome.new(ok: false, error: format_error(ex))
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
            plugin_id = alert_hash["pluginId"]?.try { |v| stringify_json_value(v) } || alert_hash["id"]?.try { |v| stringify_json_value(v) } || "unknown"
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
  end
end
