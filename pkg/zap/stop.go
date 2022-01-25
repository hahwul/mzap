package zap

import (
	"net/http"

	logger "github.com/hahwul/volt/logger"
	"github.com/sirupsen/logrus"
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
	log := logger.GetLogger(false).WithField("type", prefix)
	log.WithFields(logrus.Fields{
		"data1": api,
	}).Info("stoped")

	if err != nil {
		//panic(err)
	}
	defer resp.Body.Close()
}
