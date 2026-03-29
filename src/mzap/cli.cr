module Mzap
  class CLI
    private struct GlobalOptions
      property config : String
      property urls : String
      property apis : String
      property api_key : String
      property wait : Bool
      property wait_interval_seconds : Int32
      property wait_timeout_seconds : Int32
      property report_format : String
      property report_out : String
      property concurrency : Int32
      property policy : String
      property context : String
      property fail_on : String
      property retry_count : Int32
      property retry_delay_seconds : Int32
      property help : Bool

      def initialize
        @config = ""
        @urls = ""
        @apis = "http://localhost:8090"
        @api_key = ""
        @wait = false
        @wait_interval_seconds = 2
        @wait_timeout_seconds = 0
        @report_format = ""
        @report_out = ""
        @concurrency = 1
        @policy = ""
        @context = ""
        @fail_on = ""
        @retry_count = 0
        @retry_delay_seconds = 5
        @help = false
      end
    end

    private struct ProvidedOptions
      property config : Bool
      property urls : Bool
      property apis : Bool
      property api_key : Bool
      property wait : Bool
      property wait_interval_seconds : Bool
      property wait_timeout_seconds : Bool
      property report_format : Bool
      property report_out : Bool
      property concurrency : Bool
      property policy : Bool
      property context : Bool
      property fail_on : Bool
      property retry_count : Bool
      property retry_delay_seconds : Bool

      def initialize
        @config = false
        @urls = false
        @apis = false
        @api_key = false
        @wait = false
        @wait_interval_seconds = false
        @wait_timeout_seconds = false
        @report_format = false
        @report_out = false
        @concurrency = false
        @policy = false
        @context = false
        @fail_on = false
        @retry_count = false
        @retry_delay_seconds = false
      end
    end

    HELP_TEXT = <<-TEXT
    Usage:
      mzap [command]

    Subcommands:
      ajaxspider  Start Ajax Spider scans in ZAP
      ascan       Start Active Scan jobs in ZAP
      help        Show help for a command
      pscan       Wait for Passive Scan completion in ZAP
      spider      Start Spider scans in ZAP
      stop        Stop running scans
      version     Show mzap version

    Flags:
      --apikey string        ZAP API key (omit when API key auth is disabled)
      --apis string          Comma-separated ZAP API host URLs
                             e.g. --apis http://localhost:8090,http://192.168.0.4:8090 (default "http://localhost:8090")
      --config string        Config file path (TOML supported; default: $HOME/.config/mzap/config.toml)
      --context string       ZAP context file to import before scanning
      --fail-on string       Fail with exit code 1 if alerts at or above risk level
                             (informational/low/medium/high). Implies --wait
      --report-format        Report format after scan completion (html/pdf/json/md/sarif)
      --report-out           Report output path (default: mzap-report-<timestamp>.<ext>)
      --concurrency          Number of parallel scan dispatches (default 1)
      --wait                 Wait for initiated scans to complete
      --wait-interval        Poll interval in seconds while waiting (default 2)
      --wait-timeout         Wait timeout in seconds (default 0: no timeout)
      -h, --help             Show help for mzap
      --urls string          Path to URL list file (e.g. --urls hosts.txt)
    TEXT

    SCAN_FLAGS_TEXT = <<-TEXT
    Flags:
      --urls string          Path to URL list file (e.g. --urls hosts.txt)
      --apis string          Comma-separated ZAP API host URLs (default "http://localhost:8090")
      --apikey string        ZAP API key (omit when API key auth is disabled)
      --concurrency          Number of parallel scan dispatches (default 1)
      --config string        Config file path (default: $HOME/.config/mzap/config.toml)
      --context string       ZAP context file to import before scanning
      --wait                 Wait for initiated scans to complete
      --wait-interval        Poll interval in seconds while waiting (default 2)
      --wait-timeout         Wait timeout in seconds (default 0: no timeout)
      --report-format        Report format after scan completion (html/pdf/json/md/sarif)
      --report-out           Report output path (default: mzap-report-<timestamp>.<ext>)
      -h, --help             Show help
    TEXT

    HELP_SPIDER = <<-TEXT
    Start Spider scans in ZAP

    Usage:
      mzap spider --urls <file> [flags]

    Examples:
      mzap spider --urls targets.txt --apis http://localhost:8090
      mzap spider --urls targets.txt --apis http://localhost:8090 --wait --report-format html

    #{SCAN_FLAGS_TEXT}
    TEXT

    HELP_AJAXSPIDER = <<-TEXT
    Start Ajax Spider scans in ZAP

    Usage:
      mzap ajaxspider --urls <file> [flags]

    Examples:
      mzap ajaxspider --urls targets.txt --apis http://localhost:8090
      mzap ajaxspider --urls targets.txt --apis http://localhost:8090 --wait

    #{SCAN_FLAGS_TEXT}
    TEXT

    HELP_ASCAN = <<-TEXT
    Start Active Scan jobs in ZAP

    Usage:
      mzap ascan --urls <file> [flags]

    Examples:
      mzap ascan --urls targets.txt --apis http://localhost:8090
      mzap ascan --urls targets.txt --apis http://localhost:8090 --policy "API-Minimal-Scan"
      mzap ascan --urls targets.txt --apis http://localhost:8090 --wait --report-format html

    #{SCAN_FLAGS_TEXT}
      --policy string        ZAP scan policy name for active scan
    TEXT

    PSCAN_FLAGS_TEXT = <<-TEXT
    Flags:
      --apis string          Comma-separated ZAP API host URLs (default "http://localhost:8090")
      --apikey string        ZAP API key (omit when API key auth is disabled)
      --config string        Config file path (default: $HOME/.config/mzap/config.toml)
      --wait-interval        Poll interval in seconds while waiting (default 2)
      --wait-timeout         Wait timeout in seconds (default 0: no timeout)
      --report-format        Report format after scan completion (html/pdf/json/md/sarif)
      --report-out           Report output path (default: mzap-report-<timestamp>.<ext>)
      -h, --help             Show help
    TEXT

    HELP_PSCAN = <<-TEXT
    Wait for Passive Scan completion in ZAP

    Usage:
      mzap pscan [flags]

    Examples:
      mzap pscan --apis http://localhost:8090
      mzap pscan --apis http://localhost:8090 --wait-timeout 300 --report-format html

    #{PSCAN_FLAGS_TEXT}
    TEXT

    HELP_STOP = <<-TEXT
    Stop running scans

    Usage:
      mzap stop <type> [flags]

    Types:
      spider       Stop all Spider scans
      ajaxspider   Stop Ajax Spider scans
      ascan        Stop all Active Scans
      all          Stop all scan types

    Examples:
      mzap stop spider --apis http://localhost:8090
      mzap stop all --apis http://localhost:8090

    Flags:
      --apis string          Comma-separated ZAP API host URLs (default "http://localhost:8090")
      --apikey string        ZAP API key (omit when API key auth is disabled)
      --config string        Config file path (default: $HOME/.config/mzap/config.toml)
      -h, --help             Show help
    TEXT

    HELP_VERSION = <<-TEXT
    Show mzap version

    Usage:
      mzap version
    TEXT

    SUBCOMMAND_HELP = {
      "spider"     => HELP_SPIDER,
      "ajaxspider" => HELP_AJAXSPIDER,
      "ascan"      => HELP_ASCAN,
      "pscan"      => HELP_PSCAN,
      "stop"       => HELP_STOP,
      "version"    => HELP_VERSION,
    }

    STRING_FLAGS = {"--config", "--apikey", "--urls", "--apis", "--report-format", "--report-out", "--policy", "--context", "--fail-on"}
    INT_FLAGS    = {"--wait-interval", "--wait-timeout", "--concurrency", "--retry", "--retry-delay"}

    def self.run(argv : Array(String) = ARGV, stdout_io : IO = STDOUT, stderr_io : IO = STDERR) : Int32
      Banner.show(stderr_io)

      options, args, provided_options = begin
        parse_global_options(argv)
      rescue ex : ArgumentError
        stderr_io.puts ex.message || ex.to_s
        return 1
      end

      scan_commands = {"spider", "ajaxspider", "ascan", "pscan"}
      command = args.empty? ? "" : args[0]
      scan_command = scan_commands.includes?(command)

      begin
        config_options = Config.load_options(options.config)
        options = apply_config_options(options, config_options, provided_options, scan_command)
      rescue ex : ArgumentError
        stderr_io.puts ex.message || ex.to_s
        return 1
      end

      options = apply_env_options(options, provided_options, scan_command)

      Config.show_config_notice(config_options.path, stdout_io)

      if options.help || args.empty?
        stdout_io.puts HELP_TEXT
        return 0
      end

      command_args = args[1..]
      reporter = Reporter.new(stdout_io, stderr_io)
      report_format = options.report_format.downcase

      if options.concurrency <= 0
        stderr_io.puts "--concurrency must be greater than 0"
        return 1
      end

      if options.retry_count < 0
        stderr_io.puts "--retry must be 0 or greater"
        return 1
      end

      if options.retry_delay_seconds < 0
        stderr_io.puts "--retry-delay must be 0 or greater"
        return 1
      end

      if !options.context.empty? && !File.exists?(options.context)
        stderr_io.puts "Context file not found: #{options.context}"
        return 1
      end

      fail_on = options.fail_on.downcase
      unless fail_on.empty? || {"informational", "low", "medium", "high"}.includes?(fail_on)
        stderr_io.puts "--fail-on supports only informational, low, medium, or high"
        return 1
      end

      if options.wait_interval_seconds <= 0
        stderr_io.puts "--wait-interval must be greater than 0"
        return 1
      end

      if options.wait_timeout_seconds < 0
        stderr_io.puts "--wait-timeout must be 0 or greater"
        return 1
      end

      unless report_format.empty? || {"html", "pdf", "json", "md", "sarif"}.includes?(report_format)
        stderr_io.puts "--report-format supports only html, pdf, json, md, or sarif"
        return 1
      end

      if !options.report_out.empty? && report_format.empty?
        stderr_io.puts "--report-out requires --report-format (html or pdf)"
        return 1
      end

      if (options.wait || !report_format.empty?) && !scan_commands.includes?(command)
        stderr_io.puts "--wait and report options are only available for spider/ajaxspider/ascan/pscan"
        return 1
      end

      zap_options = Options.new(
        api_key: options.api_key,
        wait_for_completion: command == "pscan" ? true : (options.wait || !report_format.empty? || !fail_on.empty?),
        wait_interval_seconds: options.wait_interval_seconds,
        wait_timeout_seconds: options.wait_timeout_seconds,
        report_format: report_format,
        report_out: options.report_out,
        concurrency: options.concurrency,
        policy: options.policy,
        context: options.context,
        fail_on: fail_on,
        retry_count: options.retry_count,
        retry_delay_seconds: options.retry_delay_seconds,
      )

      stdin_temp_file : String? = nil
      if options.urls == "-"
        stdin_temp_file = File.tempname("mzap-stdin")
        File.write(stdin_temp_file, STDIN.gets_to_end)
        options.urls = stdin_temp_file
      end

      begin
        case command
        when "spider", "ajaxspider", "ascan"
          if options.urls.empty?
            stdout_io.puts "Please input --urls flag"
            return 1
          end
          unless File.exists?(options.urls)
            stderr_io.puts "No such file: #{options.urls}"
            return 1
          end
          fail_on_triggered = case command
                              when "spider"     then Client.spider(options.urls, apis: options.apis, options: zap_options, reporter: reporter)
                              when "ajaxspider" then Client.ajax_spider(options.urls, apis: options.apis, options: zap_options, reporter: reporter)
                              when "ascan"      then Client.active_scan(options.urls, apis: options.apis, options: zap_options, reporter: reporter)
                              else                   false
                              end
          return 1 if fail_on_triggered
        when "pscan"
          fail_on_triggered = Client.passive_scan(options.apis, options: zap_options, reporter: reporter)
          return 1 if fail_on_triggered
        when "stop"
          if command_args.empty?
            stdout_io.puts "Please input scanning mode for stop"
            return 1
          else
            case command_args[0]
            when "spider"
              Client.stop_spider(options.apis, options: zap_options, reporter: reporter)
            when "ascan"
              Client.stop_active_scan(options.apis, options: zap_options, reporter: reporter)
            when "ajaxspider"
              Client.stop_ajax_spider(options.apis, options: zap_options, reporter: reporter)
            when "all"
              Client.stop_spider(options.apis, options: zap_options, reporter: reporter)
              Client.stop_ajax_spider(options.apis, options: zap_options, reporter: reporter)
              Client.stop_active_scan(options.apis, options: zap_options, reporter: reporter)
            else
              stdout_io.puts "Please input scanning mode for stop (spider/ascan/ajaxspider/all)"
              return 1
            end
          end
        when "version"
          stdout_io.puts VERSION
        when "help"
          if command_args.empty?
            stdout_io.puts HELP_TEXT
          elsif text = SUBCOMMAND_HELP[command_args[0]]?
            stdout_io.puts text
          else
            stdout_io.puts "Unknown command: #{command_args[0]}"
            stdout_io.puts HELP_TEXT
            return 1
          end
        else
          stdout_io.puts HELP_TEXT
          return 1
        end
      rescue ex
        stderr_io.puts ex.message || ex.to_s
        return 1
      ensure
        if stdin_temp_file && File.exists?(stdin_temp_file)
          File.delete(stdin_temp_file)
        end
      end

      0
    end

    private def self.parse_global_options(argv : Array(String)) : {GlobalOptions, Array(String), ProvidedOptions}
      options = GlobalOptions.new
      provided = ProvidedOptions.new
      remaining = [] of String

      index = 0
      while index < argv.size
        arg = argv[index]

        result = parse_single_option(arg, argv, index, options, provided)
        if result
          adv, options, provided = result
          index += adv
        else
          remaining << arg
          index += 1
        end
      end

      {options, remaining, provided}
    end

    private def self.parse_single_option(
      arg : String,
      argv : Array(String),
      index : Int32,
      options : GlobalOptions,
      provided : ProvidedOptions,
    ) : {Int32, GlobalOptions, ProvidedOptions}?
      if arg == "--wait"
        options.wait = true
        provided.wait = true
        return {1, options, provided}
      end

      if arg == "-h" || arg == "--help"
        options.help = true
        return {1, options, provided}
      end

      if string_flag?(arg)
        value = parse_string_option(arg, argv[index + 1]?, true)
        options, provided = assign_string_option(options, provided, arg, value)
        return {2, options, provided}
      end

      if int_flag?(arg)
        value = parse_int_option(arg, argv[index + 1]?)
        options, provided = assign_int_option(options, provided, arg, value)
        return {2, options, provided}
      end

      parsed_equals, options, provided = parse_equals_option(arg, options, provided)
      if parsed_equals
        return {1, options, provided}
      end

      if arg.starts_with?('-')
        raise ArgumentError.new("Unknown option: #{arg}")
      end

      nil
    end

    private macro apply_config_field(updated, provided_options, config_options, provided_field, config_field, target_field)
      unless {{provided_options}}.{{provided_field}}
        if value = {{config_options}}.{{config_field}}
          {{updated}}.{{target_field}} = value
        end
      end
    end

    private def self.apply_config_options(
      options : GlobalOptions,
      config_options : Config::FileOptions,
      provided_options : ProvidedOptions,
      scan_command : Bool,
    ) : GlobalOptions
      updated = options

      apply_config_field(updated, provided_options, config_options, config, path, config)
      apply_config_field(updated, provided_options, config_options, urls, urls, urls)
      apply_config_field(updated, provided_options, config_options, apis, apis, apis)
      apply_config_field(updated, provided_options, config_options, api_key, api_key, api_key)

      return updated unless scan_command

      apply_config_field(updated, provided_options, config_options, wait, wait, wait)
      apply_config_field(updated, provided_options, config_options, wait_interval_seconds, wait_interval_seconds, wait_interval_seconds)
      apply_config_field(updated, provided_options, config_options, wait_timeout_seconds, wait_timeout_seconds, wait_timeout_seconds)
      apply_config_field(updated, provided_options, config_options, report_format, report_format, report_format)
      apply_config_field(updated, provided_options, config_options, report_out, report_out, report_out)
      apply_config_field(updated, provided_options, config_options, concurrency, concurrency, concurrency)
      apply_config_field(updated, provided_options, config_options, policy, policy, policy)
      apply_config_field(updated, provided_options, config_options, context, context, context)
      apply_config_field(updated, provided_options, config_options, fail_on, fail_on, fail_on)
      apply_config_field(updated, provided_options, config_options, retry_count, retry_count, retry_count)
      apply_config_field(updated, provided_options, config_options, retry_delay_seconds, retry_delay_seconds, retry_delay_seconds)

      updated
    end

    private def self.apply_env_options(
      options : GlobalOptions,
      provided_options : ProvidedOptions,
      scan_command : Bool,
    ) : GlobalOptions
      updated = options

      unless provided_options.urls
        if value = ENV["MZAP_URLS"]?
          updated.urls = value unless value.empty?
        end
      end
      unless provided_options.apis
        if value = ENV["MZAP_APIS"]?
          updated.apis = value unless value.empty?
        end
      end
      unless provided_options.api_key
        if value = ENV["MZAP_APIKEY"]?
          updated.api_key = value unless value.empty?
        end
      end

      return updated unless scan_command

      unless provided_options.wait
        if value = ENV["MZAP_WAIT"]?
          updated.wait = {"true", "1", "yes"}.includes?(value.downcase)
        end
      end
      unless provided_options.wait_interval_seconds
        if value = ENV["MZAP_WAIT_INTERVAL"]?
          if parsed = value.to_i?
            updated.wait_interval_seconds = parsed
          end
        end
      end
      unless provided_options.wait_timeout_seconds
        if value = ENV["MZAP_WAIT_TIMEOUT"]?
          if parsed = value.to_i?
            updated.wait_timeout_seconds = parsed
          end
        end
      end
      unless provided_options.report_format
        if value = ENV["MZAP_REPORT_FORMAT"]?
          updated.report_format = value unless value.empty?
        end
      end
      unless provided_options.report_out
        if value = ENV["MZAP_REPORT_OUT"]?
          updated.report_out = value unless value.empty?
        end
      end
      unless provided_options.concurrency
        if value = ENV["MZAP_CONCURRENCY"]?
          if parsed = value.to_i?
            updated.concurrency = parsed
          end
        end
      end
      unless provided_options.policy
        if value = ENV["MZAP_POLICY"]?
          updated.policy = value unless value.empty?
        end
      end
      unless provided_options.context
        if value = ENV["MZAP_CONTEXT"]?
          updated.context = value unless value.empty?
        end
      end
      unless provided_options.fail_on
        if value = ENV["MZAP_FAIL_ON"]?
          updated.fail_on = value unless value.empty?
        end
      end
      unless provided_options.retry_count
        if value = ENV["MZAP_RETRY"]?
          if parsed = value.to_i?
            updated.retry_count = parsed
          end
        end
      end
      unless provided_options.retry_delay_seconds
        if value = ENV["MZAP_RETRY_DELAY"]?
          if parsed = value.to_i?
            updated.retry_delay_seconds = parsed
          end
        end
      end

      updated
    end

    private def self.string_flag?(arg : String) : Bool
      STRING_FLAGS.includes?(arg)
    end

    private def self.int_flag?(arg : String) : Bool
      INT_FLAGS.includes?(arg)
    end

    private def self.parse_equals_option(
      arg : String,
      options : GlobalOptions,
      provided : ProvidedOptions,
    ) : {Bool, GlobalOptions, ProvidedOptions}
      pair = split_equals_option(arg)
      return {false, options, provided} unless pair

      flag, raw_value = pair
      if string_flag?(flag)
        value = parse_string_option(flag, raw_value)
        options, provided = assign_string_option(options, provided, flag, value)
        return {true, options, provided}
      end

      if int_flag?(flag)
        value = parse_int_option(flag, raw_value)
        options, provided = assign_int_option(options, provided, flag, value)
        return {true, options, provided}
      end

      {false, options, provided}
    end

    private def self.split_equals_option(arg : String) : {String, String?}?
      return nil unless arg.starts_with?("--")

      index = arg.index('=')
      return nil unless index

      flag = arg[0...index]
      raw_value = arg[(index + 1)..-1]?
      {flag, raw_value}
    end

    private def self.assign_string_option(
      options : GlobalOptions,
      provided : ProvidedOptions,
      flag : String,
      value : String,
    ) : {GlobalOptions, ProvidedOptions}
      case flag
      when "--config"
        options.config = value
        provided.config = true
      when "--apikey"
        options.api_key = value
        provided.api_key = true
      when "--urls"
        options.urls = value
        provided.urls = true
      when "--apis"
        options.apis = value
        provided.apis = true
      when "--report-format"
        options.report_format = value
        provided.report_format = true
      when "--report-out"
        options.report_out = value
        provided.report_out = true
      when "--policy"
        options.policy = value
        provided.policy = true
      when "--context"
        options.context = value
        provided.context = true
      when "--fail-on"
        options.fail_on = value
        provided.fail_on = true
      else
        raise ArgumentError.new("Unknown option: #{flag}")
      end

      {options, provided}
    end

    private def self.assign_int_option(
      options : GlobalOptions,
      provided : ProvidedOptions,
      flag : String,
      value : Int32,
    ) : {GlobalOptions, ProvidedOptions}
      case flag
      when "--wait-interval"
        options.wait_interval_seconds = value
        provided.wait_interval_seconds = true
      when "--wait-timeout"
        options.wait_timeout_seconds = value
        provided.wait_timeout_seconds = true
      when "--concurrency"
        options.concurrency = value
        provided.concurrency = true
      when "--retry"
        options.retry_count = value
        provided.retry_count = true
      when "--retry-delay"
        options.retry_delay_seconds = value
        provided.retry_delay_seconds = true
      else
        raise ArgumentError.new("Unknown option: #{flag}")
      end

      {options, provided}
    end

    private def self.parse_string_option(flag : String, value : String?, reject_dash_prefixed : Bool = false) : String
      raw = value || ""
      if raw.empty? || (reject_dash_prefixed && raw.starts_with?('-'))
        raise ArgumentError.new("Please input value for #{flag}")
      end

      raw
    end

    private def self.parse_int_option(flag : String, value : String?) : Int32
      raw = value || ""
      if raw.empty?
        raise ArgumentError.new("Please input value for #{flag}")
      end

      parsed = raw.to_i?
      if parsed.nil?
        raise ArgumentError.new("Invalid integer for #{flag}: #{raw}")
      end

      parsed
    end
  end
end
