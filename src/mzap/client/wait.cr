require "zap"

module Mzap
  # Wait/poll concern for Mzap::Client: drives status polling for spider,
  # active-scan, ajax-spider and passive-scan jobs until completion or timeout.
  module Client
    extend self

    private def wait_for_completion(
      scan_jobs : Array(ScanJob),
      ajax_wait_clients : Hash(String, Zap::Client),
      options : Options,
      reporter : Reporter = Reporter.new,
    ) : Nil
      pending_scan_jobs = scan_jobs.dup
      pending_ajax = ajax_wait_clients.to_a
      if pending_scan_jobs.empty? && pending_ajax.empty?
        return
      end

      reporter.info("wait", "start")
      started_at = Time.utc
      total_scan_jobs = pending_scan_jobs.size
      total_ajax_hosts = pending_ajax.size
      completed_scan_jobs = 0
      completed_ajax_hosts = 0
      poll_failures = 0
      last_poll_failure = {} of String => String

      timed_out = run_poll_loop(started_at, options) do
        pending_scan_jobs.reject! do |job|
          outcome = poll_scan_job(job, reporter, last_poll_failure)
          completed_scan_jobs += 1 if outcome.completed
          poll_failures += 1 if outcome.poll_failed
          outcome.completed
        end

        pending_ajax.reject! do |(api_host, zap_client)|
          outcome = poll_ajax_status(api_host, zap_client, reporter, last_poll_failure)
          completed_ajax_hosts += 1 if outcome.completed
          poll_failures += 1 if outcome.poll_failed
          outcome.completed
        end

        pending_scan_jobs.empty? && pending_ajax.empty?
      end

      if timed_out
        pending_scan_jobs.each do |job|
          reporter.warn("wait", "timeout", job.api_host, "#{job.type}:#{job.target}")
        end
        pending_ajax.each do |(api_host, _)|
          reporter.warn("wait", "timeout", api_host, "ajax-spider")
        end
      end

      reporter.info("wait", "summary scan_completed=#{completed_scan_jobs}/#{total_scan_jobs} ajax_completed=#{completed_ajax_hosts}/#{total_ajax_hosts} poll_failures=#{poll_failures} timed_out=#{timed_out}")
    end

    # Polls passive-scan completion (recordsToScan -> 0) across all hosts until each
    # settles or the wait timeout elapses. Shared by the `pscan` command and the
    # post-import settle step. Progress is logged under `category`.
    private def wait_for_passive_scan(
      api_hosts : Array(String),
      clients : Hash(String, Zap::Client),
      options : Options,
      reporter : Reporter,
      category : String = "passive-scan",
    ) : Nil
      pending = api_hosts.uniq.map { |host| {host, clients[host]} }
      reporter.info(category, "waiting for #{pending.size} host(s)")

      started_at = Time.utc
      poll_failures = 0
      completed_hosts = 0
      last_poll_failure = {} of String => String

      timed_out = run_poll_loop(started_at, options) do
        pending.reject! do |(api_host, zap_client)|
          outcome = poll_pscan_status(api_host, zap_client, reporter, last_poll_failure)
          completed_hosts += 1 if outcome.completed
          poll_failures += 1 if outcome.poll_failed
          outcome.completed
        end
        pending.empty?
      end

      if timed_out
        pending.each do |(api_host, _)|
          reporter.warn(category, "timeout", api_host)
        end
      end

      reporter.info(category, "summary completed=#{completed_hosts}/#{api_hosts.uniq.size} poll_failures=#{poll_failures} timed_out=#{timed_out}")
    end

    private def poll_scan_job(
      job : ScanJob,
      reporter : Reporter,
      last_poll_failure : Hash(String, String),
    ) : PollOutcome
      key = "#{job.api_host}|#{job.type}:#{job.target}"
      poll = check_scan_status(job)

      if poll.completed
        if reason = poll.failure_reason
          reporter.warn("wait", "completed with error #{reason}", job.api_host, "#{job.type}:#{job.target}")
        else
          reporter.info("wait", "complete", job.api_host, "#{job.type}:#{job.target}")
        end
        last_poll_failure.delete(key)
        PollOutcome.new(completed: true, poll_failed: false)
      elsif reason = poll.failure_reason
        if last_poll_failure[key]? != reason
          reporter.warn("wait", "status check failed #{reason}", job.api_host, "#{job.type}:#{job.target}")
          last_poll_failure[key] = reason
        end
        PollOutcome.new(completed: false, poll_failed: true)
      else
        PollOutcome.new(completed: false, poll_failed: false)
      end
    end

    private def poll_ajax_status(
      api_host : String,
      zap_client : Zap::Client,
      reporter : Reporter,
      last_poll_failure : Hash(String, String),
    ) : PollOutcome
      key = "#{api_host}|ajax-spider"

      begin
        result = zap_client.ajax_spider.status
        status = extract_status_string(result)
        if status.nil?
          reason = "(missing status value)"
          if last_poll_failure[key]? != reason
            reporter.warn("wait", "status check failed #{reason}", api_host, "ajax-spider")
            last_poll_failure[key] = reason
          end
          return PollOutcome.new(completed: false, poll_failed: true)
        end

        if status_indicates_done?(status)
          if status_indicates_error?(status)
            reporter.warn("wait", "completed with error (scan ended with status: #{status.strip})", api_host, "ajax-spider")
          else
            reporter.info("wait", "complete", api_host, "ajax-spider")
          end
          last_poll_failure.delete(key)
          PollOutcome.new(completed: true, poll_failed: false)
        else
          PollOutcome.new(completed: false, poll_failed: false)
        end
      rescue ex : Exception
        reason = format_error(ex)
        if last_poll_failure[key]? != reason
          reporter.warn("wait", "status check failed #{reason}", api_host, "ajax-spider")
          last_poll_failure[key] = reason
        end
        PollOutcome.new(completed: false, poll_failed: true)
      end
    end

    private def poll_pscan_status(
      api_host : String,
      zap_client : Zap::Client,
      reporter : Reporter,
      last_poll_failure : Hash(String, String),
    ) : PollOutcome
      key = "#{api_host}|passive-scan"

      begin
        result = zap_client.pscan.records_to_scan
        records_value = result.as_h["recordsToScan"]?
        if records_value.nil?
          reason = "(missing recordsToScan value)"
          if last_poll_failure[key]? != reason
            reporter.warn("passive-scan", "status check failed #{reason}", api_host)
            last_poll_failure[key] = reason
          end
          return PollOutcome.new(completed: false, poll_failed: true)
        end

        records_str = stringify_json_value(records_value)
        records = records_str.to_i?
        if records.nil?
          reason = "(invalid recordsToScan value: #{records_str})"
          if last_poll_failure[key]? != reason
            reporter.warn("passive-scan", "status check failed #{reason}", api_host)
            last_poll_failure[key] = reason
          end
          return PollOutcome.new(completed: false, poll_failed: true)
        end

        if records <= 0
          reporter.info("passive-scan", "complete", api_host)
          last_poll_failure.delete(key)
          PollOutcome.new(completed: true, poll_failed: false)
        else
          PollOutcome.new(completed: false, poll_failed: false)
        end
      rescue ex : Exception
        reason = format_error(ex)
        if last_poll_failure[key]? != reason
          reporter.warn("passive-scan", "status check failed #{reason}", api_host)
          last_poll_failure[key] = reason
        end
        PollOutcome.new(completed: false, poll_failed: true)
      end
    end

    private def check_scan_status(job : ScanJob) : WaitPollResult
      result = case job.type
               when "spider"
                 scan_id = job.scan_id.to_i? || -1
                 job.zap_client.spider.status(scan_id)
               when "active-scan"
                 scan_id = job.scan_id.to_i? || -1
                 job.zap_client.ascan.status(scan_id)
               when "client-spider"
                 scan_id = job.scan_id.to_i? || -1
                 job.zap_client.client_spider.status(scan_id)
               else
                 return WaitPollResult.new(false, "(unknown scan type)")
               end

      status = extract_status_string(result)
      if status.nil?
        return WaitPollResult.new(false, "(missing status value)")
      end

      if status_indicates_done?(status)
        if status_indicates_error?(status)
          return WaitPollResult.new(true, "(scan ended with status: #{status.strip})")
        end
        return WaitPollResult.new(true, nil)
      end

      WaitPollResult.new(false, nil)
    rescue ex : Exception
      WaitPollResult.new(false, format_error(ex))
    end

    # Drives a polling loop until the yielded block reports completion (returns true)
    # or the configured wait timeout elapses. Centralizes the timeout check and the
    # minimum one-second poll interval. Returns true only when the loop stopped on
    # timeout, so callers can emit their own per-target timeout diagnostics.
    private def run_poll_loop(started_at : Time, options : Options, &) : Bool
      loop do
        return false if yield
        return true if wait_timeout?(started_at, options.wait_timeout_seconds)
        sleep Math.max(options.wait_interval_seconds, 1).seconds
      end
    end

    private def wait_timeout?(started_at : Time, timeout_seconds : Int32) : Bool
      return false if timeout_seconds <= 0
      (Time.utc - started_at).total_seconds >= timeout_seconds
    end

    private def status_indicates_done?(status : String) : Bool
      normalized = status.strip.downcase
      if percentage = normalized.to_i?
        return percentage >= 100
      end

      !RUNNING_STATUSES.includes?(normalized)
    end

    private def status_indicates_error?(status : String) : Bool
      normalized = status.strip.downcase
      ERROR_STATUSES.includes?(normalized)
    end
  end
end
