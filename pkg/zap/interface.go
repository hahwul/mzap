package zap

import (
	"strings"
)

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

// StopSpider is interface of stop spider
func StopSpider(apis string){
	arrayAPIs := strings.Split(apis, ",")
	for _,v := range arrayAPIs{
		Stop(v,SpiderStop)
	}
}

// StopActiveScan is interface of stop ascan
func StopActiveScan(apis string){
	arrayAPIs := strings.Split(apis, ",")
	for _,v := range arrayAPIs{
		Stop(v,AScanStop)
	}

}

// StopAjaxSpider is interface of stop ajax spider
func StopAjaxSpider(apis string){
	arrayAPIs := strings.Split(apis, ",")
	for _,v := range arrayAPIs{
		Stop(v,AjaxSpiderStop)
	}
}
