package zap

import (
	log "github.com/sirupsen/logrus"
	"net/http"
)

// AScanStop is stop all active scans
const AScanStop = "/JSON/ascan/action/stopAllScans/?"

// SpiderStop is stop all spider scans
const SpiderStop = "/JSON/spider/action/stopAllScans/?"

// AjaxSpiderStop is stop all ajax spider scans
const AjaxSpiderStop = "/JSON/ajaxSpider/action/stopAllScans/?"

// Stop is stop zap
func Stop(api, prefix string, options OptionsZAP) {
	req, err := http.NewRequest("GET", api+prefix, nil)
	if err != nil {
		panic(err)
	}
	if options.APIKey != "" {
		req.Header.Add("X-ZAP-API-Key", options.APIKey)
	}

	client := &http.Client{}
	resp, err := client.Do(req)

	log.WithFields(log.Fields{
		"ZAP API": prefix,
	}).Info("Stoped")

	if err != nil {
		//panic(err)
	}
	defer resp.Body.Close()
}
