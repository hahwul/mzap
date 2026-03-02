require "json"

module Mzap
  module Config
    extend self

    EXTENSIONS          = %w(.toml .yaml .yml .json .hcl .ini .properties)
    DEFAULT_CONFIG_PATH = File.join(".config", "mzap", "config.toml")
    ROOT_TABLE          = "mzap"

    class FileOptions
      property path : String?
      property urls : String?
      property apis : String?
      property api_key : String?
      property wait : Bool?
      property wait_interval_seconds : Int32?
      property wait_timeout_seconds : Int32?
      property report_format : String?
      property report_out : String?

      def initialize
        @path = nil
        @urls = nil
        @apis = nil
        @api_key = nil
        @wait = nil
        @wait_interval_seconds = nil
        @wait_timeout_seconds = nil
        @report_format = nil
        @report_out = nil
      end
    end

    def load_options(config_path : String) : FileOptions
      options = FileOptions.new
      selected = resolve_config_path(config_path)
      return options unless selected

      options.path = selected
      parse_toml_options(selected, options) if File.extname(selected).downcase == ".toml"
      options
    end

    def show_config_notice(resolved_path : String?, io : IO = STDOUT) : Nil
      if resolved_path
        io.puts "Using config file: #{resolved_path}"
      end
    end

    private def resolve_config_path(config_path : String) : String?
      unless config_path.empty?
        return config_path if File.exists?(config_path)
        return nil
      end

      home = ENV["HOME"]?
      return nil unless home

      discover_default_config(home)
    end

    private def discover_default_config(home : String) : String?
      default_toml = File.join(home, DEFAULT_CONFIG_PATH)
      return default_toml if File.exists?(default_toml)

      default_base = File.join(home, ".config", "mzap", "config")
      legacy_base = File.join(home, ".mzap")
      candidates = candidate_paths(default_base) + candidate_paths(legacy_base)
      candidates.find { |candidate| File.exists?(candidate) }
    end

    private def candidate_paths(base : String) : Array(String)
      [base] + EXTENSIONS.map { |ext| "#{base}#{ext}" }
    end

    private def parse_toml_options(path : String, options : FileOptions) : Nil
      current_table = ""
      line_number = 0
      File.each_line(path) do |line|
        line_number += 1
        content = strip_toml_comment(line).strip
        next if content.empty?

        if content.starts_with?("[") && content.ends_with?("]")
          current_table = content[1...-1].strip.downcase
          next
        end

        next unless current_table.empty? || current_table == ROOT_TABLE

        key, raw_value = split_toml_assignment(content, path, line_number)
        apply_toml_option(options, key, raw_value, path, line_number)
      end
    rescue ex
      raise ArgumentError.new("Failed to parse TOML config file #{path}: #{ex.message || ex.to_s}")
    end

    private def split_toml_assignment(content : String, path : String, line_number : Int32) : {String, String}
      index = index_of_unquoted_char(content, '=')
      if index < 0
        raise ArgumentError.new("Invalid TOML syntax in #{path}:#{line_number} (expected key = value)")
      end

      key = normalize_config_key(content[0...index])
      value = content[(index + 1)..-1]?.to_s.strip

      if key.empty?
        raise ArgumentError.new("Invalid TOML key in #{path}:#{line_number}")
      end

      if value.empty?
        raise ArgumentError.new("Invalid TOML value for #{key} in #{path}:#{line_number}")
      end

      {key, value}
    end

    private def apply_toml_option(options : FileOptions, key : String, raw_value : String, path : String, line_number : Int32) : Nil
      case key
      when "apis"
        options.apis = parse_toml_apis(raw_value, path, line_number)
      when "api_key", "apikey"
        options.api_key = parse_toml_string(raw_value, key, path, line_number)
      when "urls"
        options.urls = parse_toml_string(raw_value, key, path, line_number)
      when "wait"
        options.wait = parse_toml_bool(raw_value, key, path, line_number)
      when "wait_interval", "wait_interval_seconds"
        options.wait_interval_seconds = parse_toml_int(raw_value, key, path, line_number)
      when "wait_timeout", "wait_timeout_seconds"
        options.wait_timeout_seconds = parse_toml_int(raw_value, key, path, line_number)
      when "report_format"
        options.report_format = parse_toml_string(raw_value, key, path, line_number)
      when "report_out"
        options.report_out = parse_toml_string(raw_value, key, path, line_number)
      end
    end

    private def parse_toml_apis(raw_value : String, path : String, line_number : Int32) : String
      value = raw_value.strip
      if value.starts_with?("[")
        parse_toml_string_array(value, path, line_number).join(",")
      else
        parse_toml_string(value, "apis", path, line_number)
      end
    end

    private def parse_toml_string_array(raw_value : String, path : String, line_number : Int32) : Array(String)
      value = raw_value.strip
      unless value.starts_with?("[") && value.ends_with?("]")
        raise ArgumentError.new("Invalid TOML array in #{path}:#{line_number}")
      end

      body = value[1...-1].strip
      return [] of String if body.empty?

      split_toml_array_items(body, path, line_number).map do |item|
        parse_toml_string(item, "apis", path, line_number)
      end
    end

    private def split_toml_array_items(body : String, path : String, line_number : Int32) : Array(String)
      items = [] of String
      start_index = 0

      unclosed = scan_with_quote_context(body) do |char, index, in_quotes|
        if !in_quotes && char == ','
          item = body[start_index...index].strip
          if item.empty?
            raise ArgumentError.new("Invalid TOML array item in #{path}:#{line_number}")
          end
          items << item
          start_index = index + 1
        end
      end

      if unclosed
        raise ArgumentError.new("Invalid TOML array in #{path}:#{line_number}")
      end

      tail = start_index < body.size ? body[start_index..-1].to_s.strip : ""
      if !tail.empty?
        items << tail
      elsif items.empty?
        raise ArgumentError.new("Invalid TOML array in #{path}:#{line_number}")
      end

      items
    end

    private def parse_toml_string(raw_value : String, key : String, path : String, line_number : Int32) : String
      value = raw_value.strip
      if value.starts_with?("\"") && value.ends_with?("\"") && value.size >= 2
        content = value[1...-1]
        begin
          return JSON.parse(%("#{content}")).as_s
        rescue ex
          raise ArgumentError.new("Invalid TOML string for #{key} in #{path}:#{line_number}")
        end
      end

      if value.starts_with?("'") && value.ends_with?("'") && value.size >= 2
        return value[1...-1]
      end

      raise ArgumentError.new("Invalid TOML string for #{key} in #{path}:#{line_number}")
    end

    private def parse_toml_bool(raw_value : String, key : String, path : String, line_number : Int32) : Bool
      case raw_value.strip.downcase
      when "true"
        true
      when "false"
        false
      else
        raise ArgumentError.new("Invalid TOML boolean for #{key} in #{path}:#{line_number}")
      end
    end

    private def parse_toml_int(raw_value : String, key : String, path : String, line_number : Int32) : Int32
      value = raw_value.strip.delete('_')
      parsed = value.to_i?
      if parsed.nil?
        raise ArgumentError.new("Invalid TOML integer for #{key} in #{path}:#{line_number}")
      end

      parsed
    end

    private def normalize_config_key(raw_key : String) : String
      key = raw_key.strip
      if key.starts_with?("\"") && key.ends_with?("\"") && key.size >= 2
        key = key[1...-1]
      elsif key.starts_with?("'") && key.ends_with?("'") && key.size >= 2
        key = key[1...-1]
      end

      normalized = key.downcase.gsub("-", "_")
      if normalized.starts_with?("#{ROOT_TABLE}.")
        normalized[(ROOT_TABLE.size + 1)..-1].to_s
      else
        normalized
      end
    end

    private def scan_with_quote_context(text : String, &) : Bool
      in_quotes = false
      quote_char = '\0'
      escaped = false

      text.each_char_with_index do |char, index|
        if in_quotes
          if quote_char == '"' && !escaped && char == '\\'
            escaped = true
            yield char, index, true
            next
          end

          if !escaped && char == quote_char
            in_quotes = false
          end
          escaped = false
          yield char, index, true
          next
        end

        if char == '"' || char == '\''
          in_quotes = true
          quote_char = char
          escaped = false
          yield char, index, true
          next
        end

        yield char, index, false
      end

      in_quotes
    end

    private def strip_toml_comment(line : String) : String
      comment_index = -1
      scan_with_quote_context(line) do |char, index, in_quotes|
        if comment_index < 0 && !in_quotes && char == '#'
          comment_index = index
        end
      end
      comment_index >= 0 ? line[0...comment_index] : line
    end

    private def index_of_unquoted_char(value : String, target : Char) : Int32
      result = -1
      scan_with_quote_context(value) do |char, index, in_quotes|
        if result < 0 && !in_quotes && char == target
          result = index
        end
      end
      result
    end
  end
end
