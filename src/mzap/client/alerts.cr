require "zap"

module Mzap
  # Alert concern for Mzap::Client: per-host alert summaries, the --fail-on risk
  # gate, and shared extraction of the ZAP alerts array shape.
  module Client
    extend self

    ALERTS_SUMMARY_API = "/JSON/alert/view/alertsSummary/"
    RISK_LEVELS        = {"informational" => 0, "low" => 1, "medium" => 2, "high" => 3}

    private def print_alert_summary(clients : Hash(String, Zap::Client), reporter : Reporter) : Nil
      clients.each do |api_host, zap_client|
        begin
          result = zap_client.alert.alerts_summary
          if (hash = result.as_h?) && (summary = hash["alertsSummary"]?)
            if counts = summary.as_h?
              high = counts["High"]?.try(&.as_i?) || 0
              medium = counts["Medium"]?.try(&.as_i?) || 0
              low = counts["Low"]?.try(&.as_i?) || 0
              info = counts["Informational"]?.try(&.as_i?) || 0
              reporter.info("alerts", "High: #{high}, Medium: #{medium}, Low: #{low}, Informational: #{info}", api_host)
            end
          end
        rescue ex : Exception
          reporter.warn("alerts", "summary fetch failed #{format_error(ex)}", api_host)
        end
      end
    end

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
          failed = true
          reporter.warn("fail-on", "alert check failed #{format_error(ex)} (treating as failure)", api_host)
        end
      end

      failed
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
