package zap

// Spider is interface of spider
func Spider(urls,apis string){
	Run(urls,apis,SpiderAPI)
}

// AjaxSpider is interface of ajax spider
func AjaxSpider(urls,apis string){
	Run(urls,apis,AjaxSpiderAPI)
}

// ActiveScan is interface of ascan
func ActiveScan(urls,apis string){
	Run(urls,apis,AScanAPI)
}
