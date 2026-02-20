module Mzap
  class Reporter
    def initialize(@stdout_io : IO = STDOUT, @stderr_io : IO = STDERR)
    end

    def info(type : String, message : String, data1 : String? = nil, data2 : String? = nil) : Nil
      @stdout_io.puts format("INFO", type, message, data1, data2)
    end

    def warn(type : String, message : String, data1 : String? = nil, data2 : String? = nil) : Nil
      @stderr_io.puts format("WARN", type, message, data1, data2)
    end

    private def format(level : String, type : String, message : String, data1 : String?, data2 : String?) : String
      line = ["[#{level}]", "[#{type}]"]
      line << "[#{data1}]" if data1
      line << "[#{data2}]" if data2
      line << message
      line.join(" ")
    end
  end
end
