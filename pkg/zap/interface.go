package zap

import (
	"strings"
)

// Spider is interface of spider
func Spider(urls, apis string, options OptionsZAP) {
	Run(urls, apis, SpiderAPI, options)
}

// AjaxSpider is interface of ajax spider
func AjaxSpider(urls, apis string, options OptionsZAP) {
	Run(urls, apis, AjaxSpiderAPI, options)
}

// ActiveScan is interface of ascan
func ActiveScan(urls, apis string, options OptionsZAP) {
	Run(urls, apis, AScanAPI, options)
}

// StopSpider is interface of stop spider
func StopSpider(apis string, options OptionsZAP) {
	arrayAPIs := strings.Split(apis, ",")
	for _, v := range arrayAPIs {
		Stop(v, SpiderStop, options)
	}
}

// StopActiveScan is interface of stop ascan
func StopActiveScan(apis string, options OptionsZAP) {
	arrayAPIs := strings.Split(apis, ",")
	for _, v := range arrayAPIs {
		Stop(v, AScanStop, options)
	}

}

// StopAjaxSpider is interface of stop ajax spider
func StopAjaxSpider(apis string, options OptionsZAP) {
	arrayAPIs := strings.Split(apis, ",")
	for _, v := range arrayAPIs {
		Stop(v, AjaxSpiderStop, options)
	}
}
