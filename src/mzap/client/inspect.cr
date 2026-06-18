require "zap"

module Mzap
  # Inspection / maintenance concern for Mzap::Client: discovery of active-scan
  # policies (so the --policy flag is usable) and Sites Tree export/prune for
  # ZAP 2.16+ differential/incremental scanning in CI.
  module Client
    extend self

    SCAN_POLICY_NAMES_API = "/JSON/ascan/view/scanPolicyNames/"
    ASCAN_SCANNERS_API    = "/JSON/ascan/view/scanners/"
    EXPORT_SITES_TREE_API = "/JSON/exim/action/exportSitesTree/"
    PRUNE_SITES_TREE_API  = "/JSON/exim/action/pruneSitesTree/"

    # Lists active-scan policy names per host. When `policy` is given, reports the
    # scanner counts for that policy instead, so users can tune it.
    def list_policies(apis : String, *, policy : String = "", options : Options, reporter : Reporter = Reporter.new) : Nil
      api_hosts = normalize_api_hosts(apis)
      with_zap_clients(api_hosts, options) do |clients|
        api_hosts.each do |api_host|
          zap_client = clients[api_host]
          begin
            if policy.empty?
              names = extract_named_array(zap_client.ascan.scan_policy_names, "scanPolicyNames")
              if names.empty?
                reporter.info("policies", "no scan policies found", api_host)
              else
                reporter.info("policies", "scan policies: #{names.join(", ")}", api_host)
              end
            else
              scanners = zap_client.ascan.scanners(scan_policy_name: policy).as_h?.try(&.["scanners"]?).try(&.as_a?) || [] of JSON::Any
              enabled = scanners.count { |s| s.as_h?.try(&.["enabled"]?).try(&.as_s?) == "true" }
              reporter.info("policies", "policy '#{policy}': #{scanners.size} scanner(s), #{enabled} enabled", api_host)
            end
          rescue ex : Exception
            reporter.warn("policies", "error #{format_error(ex)}", api_host)
          end
        end
      end
    end

    # Exports each host's Sites Tree to a file. NOTE: the path is resolved by the
    # ZAP daemon (not mzap), so on remote/Docker ZAP the file lands on the ZAP host.
    def export_sites_tree(apis : String, *, file_path : String, options : Options, reporter : Reporter = Reporter.new) : Nil
      run_sites_tree(apis, "export", file_path, options, reporter)
    end

    # Prunes each host's Sites Tree using a previously exported file (daemon-side
    # path, see export_sites_tree).
    def prune_sites_tree(apis : String, *, file_path : String, options : Options, reporter : Reporter = Reporter.new) : Nil
      run_sites_tree(apis, "prune", file_path, options, reporter)
    end

    private def run_sites_tree(apis : String, action : String, file_path : String, options : Options, reporter : Reporter) : Nil
      api_hosts = normalize_api_hosts(apis)
      paths = resolve_sites_tree_paths(api_hosts, file_path)
      success = 0
      failure = 0

      with_zap_clients(api_hosts, options) do |clients|
        api_hosts.uniq.each do |api_host|
          zap_client = clients[api_host]
          host_path = paths[api_host]
          begin
            case action
            when "export" then zap_client.exim.export_sites_tree(host_path)
            when "prune"  then zap_client.exim.prune_sites_tree(host_path)
            end
            success += 1
            reporter.info("sitestree", "#{action} requested (ZAP host path: #{host_path})", api_host)
          rescue ex : Exception
            failure += 1
            reporter.warn("sitestree", "#{action} error #{format_error(ex)}", api_host)
          end
        end
      end

      reporter.info("sitestree", "summary action=#{action} success=#{success} failed=#{failure}")
    end

    # Namespaces the tree file path per host when more than one distinct host is
    # targeted, mirroring how reports are split, so shared-filesystem hosts do not
    # collide.
    private def resolve_sites_tree_paths(api_hosts : Array(String), file_path : String) : Hash(String, String)
      paths = {} of String => String
      uniq = api_hosts.uniq
      if uniq.size <= 1
        uniq.each { |host| paths[host] = file_path }
        return paths
      end

      dir = File.dirname(file_path)
      ext = File.extname(file_path)
      stem = File.basename(file_path, ext)
      counts = Hash(String, Int32).new(0)
      uniq.each do |api_host|
        base = sanitize_host(api_host)
        counts[base] += 1
        suffix = counts[base]
        safe = suffix == 1 ? base : "#{base}-#{suffix}"
        name = "#{stem}-#{safe}#{ext}"
        paths[api_host] = dir == "." ? name : File.join(dir, name)
      end
      paths
    end

    private def extract_named_array(result : JSON::Any, key : String) : Array(String)
      hash = result.as_h?
      return [] of String unless hash
      arr = hash[key]?.try(&.as_a?)
      return [] of String unless arr
      arr.compact_map(&.as_s?)
    end
  end
end
