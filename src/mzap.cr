require "./mzap/version"
require "./mzap/options"
require "./mzap/banner"
require "./mzap/reporter"
require "./mzap/client"
require "./mzap/config"
require "./mzap/cli"

module Mzap
  extend self

  def spider(urls : String, *, apis : String, options : Options, reporter : Reporter = Reporter.new) : Bool
    Client.spider(urls, apis: apis, options: options, reporter: reporter)
  end

  def ajax_spider(urls : String, *, apis : String, options : Options, reporter : Reporter = Reporter.new) : Bool
    Client.ajax_spider(urls, apis: apis, options: options, reporter: reporter)
  end

  def active_scan(urls : String, *, apis : String, options : Options, reporter : Reporter = Reporter.new) : Bool
    Client.active_scan(urls, apis: apis, options: options, reporter: reporter)
  end

  def client_spider(urls : String, *, apis : String, options : Options, reporter : Reporter = Reporter.new) : Bool
    Client.client_spider(urls, apis: apis, options: options, reporter: reporter)
  end

  def passive_scan(apis : String, *, options : Options, reporter : Reporter = Reporter.new) : Bool
    Client.passive_scan(apis, options: options, reporter: reporter)
  end

  def import_api(urls : String, *, format : String, target_url : String = "", apis : String, options : Options, reporter : Reporter = Reporter.new) : Bool
    Client.import_api(urls, format: format, target_url: target_url, apis: apis, options: options, reporter: reporter)
  end

  def stop_spider(apis : String, *, options : Options, reporter : Reporter = Reporter.new) : Nil
    Client.stop_spider(apis, options: options, reporter: reporter)
  end

  def stop_active_scan(apis : String, *, options : Options, reporter : Reporter = Reporter.new) : Nil
    Client.stop_active_scan(apis, options: options, reporter: reporter)
  end

  def stop_ajax_spider(apis : String, *, options : Options, reporter : Reporter = Reporter.new) : Nil
    Client.stop_ajax_spider(apis, options: options, reporter: reporter)
  end

  def stop_client_spider(apis : String, *, options : Options, reporter : Reporter = Reporter.new) : Nil
    Client.stop_client_spider(apis, options: options, reporter: reporter)
  end

  def list_policies(apis : String, *, policy : String = "", options : Options, reporter : Reporter = Reporter.new) : Nil
    Client.list_policies(apis, policy: policy, options: options, reporter: reporter)
  end

  def export_sites_tree(apis : String, *, file_path : String, options : Options, reporter : Reporter = Reporter.new) : Nil
    Client.export_sites_tree(apis, file_path: file_path, options: options, reporter: reporter)
  end

  def prune_sites_tree(apis : String, *, file_path : String, options : Options, reporter : Reporter = Reporter.new) : Nil
    Client.prune_sites_tree(apis, file_path: file_path, options: options, reporter: reporter)
  end
end
