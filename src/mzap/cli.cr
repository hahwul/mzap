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
      end
    end

    HELP_TEXT = <<-TEXT
    Usage:
      mzap [command]

    Subcommands:
      ajaxspider  Start Ajax Spider scans in ZAP
      ascan       Start Active Scan jobs in ZAP
      help        Show help for a command
      spider      Start Spider scans in ZAP
      stop        Stop running scans
      version     Show mzap version

    Flags:
      --apikey string        ZAP API key (omit when API key auth is disabled)
      --apis string          Comma-separated ZAP API host URLs
                             e.g. --apis http://localhost:8090,http://192.168.0.4:8090 (default "http://localhost:8090")
      --config string        Config file path (TOML supported; default: $HOME/.config/mzap/config.toml)
      --report-format        Report format after scan completion (html/pdf)
      --report-out           Report output path (default: mzap-report-<timestamp>.<ext>)
      --wait                 Wait for initiated scans to complete
      --wait-interval        Poll interval in seconds while waiting (default 2)
      --wait-timeout         Wait timeout in seconds (default 0: no timeout)
      -h, --help             Show help for mzap
      --urls string          Path to URL list file (e.g. --urls hosts.txt)
    TEXT

    def self.run(argv : Array(String) = ARGV, stdout_io : IO = STDOUT, stderr_io : IO = STDERR) : Int32
      Banner.show(stderr_io)

      options, args, provided_options = begin
        parse_global_options(argv)
      rescue ex : ArgumentError
        stderr_io.puts ex.message || ex.to_s
        return 1
      end

      scan_commands = {"spider", "ajaxspider", "ascan"}
      command = args.empty? ? "" : args[0]
      scan_command = scan_commands.includes?(command)

      begin
        config_options = Config.load_options(options.config)
        options = apply_config_options(options, config_options, provided_options, scan_command)
      rescue ex : ArgumentError
        stderr_io.puts ex.message || ex.to_s
        return 1
      end

      Config.show_config_notice(options.config, stdout_io)

      if options.help || args.empty?
        stdout_io.puts HELP_TEXT
        return 0
      end

      command_args = args.size > 1 ? args[1..] : [] of String
      reporter = Reporter.new(stdout_io, stderr_io)
      report_format = options.report_format.downcase

      if options.wait_interval_seconds <= 0
        stderr_io.puts "--wait-interval must be greater than 0"
        return 1
      end

      if options.wait_timeout_seconds < 0
        stderr_io.puts "--wait-timeout must be 0 or greater"
        return 1
      end

      unless report_format.empty? || {"html", "pdf"}.includes?(report_format)
        stderr_io.puts "--report-format supports only html or pdf"
        return 1
      end

      if !options.report_out.empty? && report_format.empty?
        stderr_io.puts "--report-out requires --report-format (html or pdf)"
        return 1
      end

      if (options.wait || !report_format.empty?) && !scan_commands.includes?(command)
        stderr_io.puts "--wait and report options are only available for spider/ajaxspider/ascan"
        return 1
      end

      zap_options = Options.new(
        options.api_key,
        options.urls,
        options.wait || !report_format.empty?,
        options.wait_interval_seconds,
        options.wait_timeout_seconds,
        report_format,
        options.report_out
      )

      begin
        case command
        when "spider"
          if options.urls.empty?
            stdout_io.puts "Please input --urls flag"
            return 1
          else
            Client.spider(options.urls, options.apis, zap_options, reporter)
          end
        when "ajaxspider"
          if options.urls.empty?
            stdout_io.puts "Please input --urls flag"
            return 1
          else
            Client.ajax_spider(options.urls, options.apis, zap_options, reporter)
          end
        when "ascan"
          if options.urls.empty?
            stdout_io.puts "Please input --urls flag"
            return 1
          else
            Client.active_scan(options.urls, options.apis, zap_options, reporter)
          end
        when "stop"
          if command_args.empty?
            stdout_io.puts "Please input scanning mode for stop"
            return 1
          else
            case command_args[0]
            when "spider"
              Client.stop_spider(options.apis, zap_options, reporter)
            when "ascan"
              Client.stop_active_scan(options.apis, zap_options, reporter)
            when "ajaxspider"
              Client.stop_ajax_spider(options.apis, zap_options, reporter)
            when "all"
              Client.stop_spider(options.apis, zap_options, reporter)
              Client.stop_ajax_spider(options.apis, zap_options, reporter)
              Client.stop_active_scan(options.apis, zap_options, reporter)
            else
              stdout_io.puts "Please input scanning mode for stop (spider/ascan/ajaxspider/all)"
              return 1
            end
          end
        when "version"
          stdout_io.puts VERSION
        when "help"
          stdout_io.puts HELP_TEXT
        else
          stdout_io.puts HELP_TEXT
          return 1
        end
      rescue ex
        stderr_io.puts ex.message || ex.to_s
        return 1
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
        if arg == "--config"
          options.config = parse_string_option(arg, argv[index + 1]?, true)
          provided.config = true
          index += 2
          next
        end
        if arg.starts_with?("--config=")
          options.config = parse_string_option("--config", arg.split("=", 2)[1]?)
          provided.config = true
          index += 1
          next
        end

        if arg == "--apikey"
          options.api_key = parse_string_option(arg, argv[index + 1]?, true)
          provided.api_key = true
          index += 2
          next
        end
        if arg.starts_with?("--apikey=")
          options.api_key = parse_string_option("--apikey", arg.split("=", 2)[1]?)
          provided.api_key = true
          index += 1
          next
        end

        if arg == "--urls"
          options.urls = parse_string_option(arg, argv[index + 1]?, true)
          provided.urls = true
          index += 2
          next
        end
        if arg.starts_with?("--urls=")
          options.urls = parse_string_option("--urls", arg.split("=", 2)[1]?)
          provided.urls = true
          index += 1
          next
        end

        if arg == "--apis"
          options.apis = parse_string_option(arg, argv[index + 1]?, true)
          provided.apis = true
          index += 2
          next
        end
        if arg.starts_with?("--apis=")
          options.apis = parse_string_option("--apis", arg.split("=", 2)[1]?)
          provided.apis = true
          index += 1
          next
        end

        if arg == "--wait"
          options.wait = true
          provided.wait = true
          index += 1
          next
        end

        if arg == "--wait-interval"
          options.wait_interval_seconds = parse_int_option(arg, argv[index + 1]?)
          provided.wait_interval_seconds = true
          index += 2
          next
        end
        if arg.starts_with?("--wait-interval=")
          options.wait_interval_seconds = parse_int_option("--wait-interval", arg.split("=", 2)[1]?)
          provided.wait_interval_seconds = true
          index += 1
          next
        end

        if arg == "--wait-timeout"
          options.wait_timeout_seconds = parse_int_option(arg, argv[index + 1]?)
          provided.wait_timeout_seconds = true
          index += 2
          next
        end
        if arg.starts_with?("--wait-timeout=")
          options.wait_timeout_seconds = parse_int_option("--wait-timeout", arg.split("=", 2)[1]?)
          provided.wait_timeout_seconds = true
          index += 1
          next
        end

        if arg == "--report-format"
          options.report_format = parse_string_option(arg, argv[index + 1]?, true)
          provided.report_format = true
          index += 2
          next
        end
        if arg.starts_with?("--report-format=")
          options.report_format = parse_string_option("--report-format", arg.split("=", 2)[1]?)
          provided.report_format = true
          index += 1
          next
        end

        if arg == "--report-out"
          options.report_out = parse_string_option(arg, argv[index + 1]?, true)
          provided.report_out = true
          index += 2
          next
        end
        if arg.starts_with?("--report-out=")
          options.report_out = parse_string_option("--report-out", arg.split("=", 2)[1]?)
          provided.report_out = true
          index += 1
          next
        end

        if arg == "-h" || arg == "--help"
          options.help = true
          index += 1
          next
        end

        if arg.starts_with?('-')
          raise ArgumentError.new("Unknown option: #{arg}")
        end

        remaining << arg
        index += 1
      end

      {options, remaining, provided}
    end

    private def self.apply_config_options(
      options : GlobalOptions,
      config_options : Config::FileOptions,
      provided_options : ProvidedOptions,
      scan_command : Bool
    ) : GlobalOptions
      updated = options

      unless provided_options.config
        if value = config_options.path
          updated.config = value
        end
      end

      unless provided_options.urls
        if value = config_options.urls
          updated.urls = value
        end
      end

      unless provided_options.apis
        if value = config_options.apis
          updated.apis = value
        end
      end

      unless provided_options.api_key
        if value = config_options.api_key
          updated.api_key = value
        end
      end

      return updated unless scan_command

      unless provided_options.wait
        if value = config_options.wait
          updated.wait = value
        end
      end

      unless provided_options.wait_interval_seconds
        if value = config_options.wait_interval_seconds
          updated.wait_interval_seconds = value
        end
      end

      unless provided_options.wait_timeout_seconds
        if value = config_options.wait_timeout_seconds
          updated.wait_timeout_seconds = value
        end
      end

      unless provided_options.report_format
        if value = config_options.report_format
          updated.report_format = value
        end
      end

      unless provided_options.report_out
        if value = config_options.report_out
          updated.report_out = value
        end
      end

      updated
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

      parsed.not_nil!
    end
  end
end
