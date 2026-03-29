require "./mzap/version"
require "./mzap/options"
require "./mzap/banner"
require "./mzap/reporter"
require "./mzap/client"
require "./mzap/config"
require "./mzap/cli"

module Mzap
  extend self

  def spider(urls : String, *, apis : String, options : Options, reporter : Reporter = Reporter.new) : Nil
    Client.spider(urls, apis: apis, options: options, reporter: reporter)
  end

  def ajax_spider(urls : String, *, apis : String, options : Options, reporter : Reporter = Reporter.new) : Nil
    Client.ajax_spider(urls, apis: apis, options: options, reporter: reporter)
  end

  def active_scan(urls : String, *, apis : String, options : Options, reporter : Reporter = Reporter.new) : Nil
    Client.active_scan(urls, apis: apis, options: options, reporter: reporter)
  end

  def passive_scan(apis : String, *, options : Options, reporter : Reporter = Reporter.new) : Nil
    Client.passive_scan(apis, options: options, reporter: reporter)
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
end
