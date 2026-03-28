module Mzap
  struct Options
    getter api_key : String
    getter wait_for_completion : Bool
    getter wait_interval_seconds : Int32
    getter wait_timeout_seconds : Int32
    getter report_format : String
    getter report_out : String

    def initialize(
      *,
      @api_key : String = "",
      @wait_for_completion : Bool = false,
      @wait_interval_seconds : Int32 = 2,
      @wait_timeout_seconds : Int32 = 0,
      @report_format : String = "",
      @report_out : String = "",
    )
    end

    def wait_enabled? : Bool
      @wait_for_completion || report_enabled?
    end

    def report_enabled? : Bool
      !@report_format.empty?
    end
  end
end
