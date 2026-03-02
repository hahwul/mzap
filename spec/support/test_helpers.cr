require "file_utils"
require "http/params"
require "http/server"

record CapturedRequest, path : String, query : String?, api_key : String?

class TestServer
  getter url : String

  def initialize(@handler : Proc(HTTP::Server::Context, Nil)? = nil)
    @requests = [] of CapturedRequest
    @lock = Mutex.new
    @server = HTTP::Server.new do |context|
      request = context.request
      @lock.synchronize do
        @requests << CapturedRequest.new(
          request.path,
          request.query,
          request.headers["X-ZAP-API-Key"]?
        )
      end
      if @handler
        @handler.not_nil!.call(context)
      else
        context.response.status_code = 200
        context.response.print("ok")
      end
    end

    address = @server.bind_tcp("127.0.0.1", 0)
    @url = "http://#{address.address}:#{address.port}"
    @done = Channel(Nil).new

    spawn do
      begin
        @server.listen
      rescue ex : Exception
      ensure
        @done.send(nil)
      end
    end
  end

  def requests : Array(CapturedRequest)
    @lock.synchronize { @requests.dup }
  end

  def close : Nil
    @server.close
    @done.receive
  end
end

def with_target_file(lines : Array(String), &block : String ->)
  path = File.tempname("mzap-targets")
  File.write(path, lines.join("\n") + "\n")
  begin
    yield path
  ensure
    File.delete(path) if File.exists?(path)
  end
end

def with_temp_home(&block : String ->)
  temp_home = File.tempname("mzap-home")
  Dir.mkdir_p(temp_home)
  previous_home = ENV["HOME"]?
  ENV["HOME"] = temp_home

  begin
    yield temp_home
  ensure
    if previous_home
      ENV["HOME"] = previous_home
    else
      ENV.delete("HOME")
    end
    FileUtils.rm_rf(temp_home)
  end
end

def stop_path(path : String) : String
  path.ends_with?("?") ? path[0...-1] : path
end

def sanitized_host_for_report(value : String) : String
  normalized = value.gsub(/[^a-zA-Z0-9]+/, "-").gsub(/^-+/, "").gsub(/-+$/, "")
  normalized.empty? ? "host" : normalized
end

class RaisingIO < IO
  def read(slice : Bytes) : Int32
    0
  end

  def write(slice : Bytes) : Nil
    raise Exception.new("Mocked unexpected Exception")
  end
end
