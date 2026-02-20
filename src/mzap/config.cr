module Mzap
  module Config
    extend self

    EXTENSIONS = %w(.json .toml .yaml .yml .hcl .ini .properties)

    def show_config_notice(config_path : String, io : IO = STDOUT) : Nil
      unless config_path.empty?
        if File.exists?(config_path)
          io.puts "Using config file: #{config_path}"
        end
        return
      end

      home = ENV["HOME"]?
      return unless home

      base = File.join(home, ".mzap")
      candidates = [base] + EXTENSIONS.map { |ext| "#{base}#{ext}" }
      if selected = candidates.find { |candidate| File.exists?(candidate) }
        io.puts "Using config file: #{selected}"
      end
    end
  end
end
