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

    HELP_TEXT = <<-TEXT
    Usage:
      mzap [command]

    Available Commands:
      ajaxspider  Add AjaxSpider ZAP
      ascan       Add ActiveScan ZAP
      help        Help about any command
      spider      Add ZAP spider
      stop        Stop Scanning
      version     Show version

    Flags:
          --apikey string   ZAP API Key / if you disable apikey, not use this option
          --apis string     ZAP API Host(s) address
                            e.g --apis http://localhost:8090,http://192.168.0.4:8090 (default "http://localhost:8090")
      --config string   config file (default is $HOME/.mzap.yaml)
          --report-format   Report format after scan complete (html/pdf)
          --report-out      Output report path (default: mzap-report-<timestamp>.<ext>)
          --wait            Wait until initiated scans complete
          --wait-interval   Poll interval in seconds for waiting (default 2)
          --wait-timeout    Timeout seconds for waiting (default 0: no timeout)
      -h, --help            help for mzap
          --urls string     URL list file / e.g --urls hosts.txt
    TEXT

    def self.run(argv : Array(String) = ARGV, stdout_io : IO = STDOUT, stderr_io : IO = STDERR) : Int32
      Banner.show(stderr_io)

      options, args = begin
        parse_global_options(argv)
      rescue ex : ArgumentError
        stderr_io.puts ex.message || ex.to_s
        return 1
      end
      Config.show_config_notice(options.config, stdout_io)

      if options.help || args.empty?
        stdout_io.puts HELP_TEXT
        return 0
      end

      command = args[0]
      command_args = args.size > 1 ? args[1..] : [] of String
      reporter = Reporter.new(stdout_io, stderr_io)
      scan_commands = {"spider", "ajaxspider", "ascan"}
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

    private def self.parse_global_options(argv : Array(String)) : {GlobalOptions, Array(String)}
      options = GlobalOptions.new
      remaining = [] of String

      index = 0
      while index < argv.size
        arg = argv[index]
        if arg == "--config"
          options.config = argv[index + 1]? || ""
          index += 2
          next
        end
        if arg.starts_with?("--config=")
          options.config = arg.split("=", 2)[1]
          index += 1
          next
        end

        if arg == "--apikey"
          options.api_key = argv[index + 1]? || ""
          index += 2
          next
        end
        if arg.starts_with?("--apikey=")
          options.api_key = arg.split("=", 2)[1]
          index += 1
          next
        end

        if arg == "--urls"
          options.urls = argv[index + 1]? || ""
          index += 2
          next
        end
        if arg.starts_with?("--urls=")
          options.urls = arg.split("=", 2)[1]
          index += 1
          next
        end

        if arg == "--apis"
          options.apis = argv[index + 1]? || options.apis
          index += 2
          next
        end
        if arg.starts_with?("--apis=")
          options.apis = arg.split("=", 2)[1]
          index += 1
          next
        end

        if arg == "--wait"
          options.wait = true
          index += 1
          next
        end

        if arg == "--wait-interval"
          options.wait_interval_seconds = parse_int_option(arg, argv[index + 1]?)
          index += 2
          next
        end
        if arg.starts_with?("--wait-interval=")
          options.wait_interval_seconds = parse_int_option("--wait-interval", arg.split("=", 2)[1]?)
          index += 1
          next
        end

        if arg == "--wait-timeout"
          options.wait_timeout_seconds = parse_int_option(arg, argv[index + 1]?)
          index += 2
          next
        end
        if arg.starts_with?("--wait-timeout=")
          options.wait_timeout_seconds = parse_int_option("--wait-timeout", arg.split("=", 2)[1]?)
          index += 1
          next
        end

        if arg == "--report-format"
          options.report_format = argv[index + 1]? || ""
          index += 2
          next
        end
        if arg.starts_with?("--report-format=")
          options.report_format = arg.split("=", 2)[1]
          index += 1
          next
        end

        if arg == "--report-out"
          options.report_out = argv[index + 1]? || ""
          index += 2
          next
        end
        if arg.starts_with?("--report-out=")
          options.report_out = arg.split("=", 2)[1]
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

      {options, remaining}
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
