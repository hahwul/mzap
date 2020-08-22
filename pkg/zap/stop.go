package zap

import (
	"net/http"
	log "github.com/sirupsen/logrus"
)

const AScanStop = "/JSON/ascan/action/stopAllScans/?"
const SpiderStop = "/JSON/spider/action/stopAllScans/?"
const AjaxSpiderStop = "/JSON/ajaxSpider/action/stopAllScans/?"

func Stop(api, prefix string){
	req, err := http.NewRequest("GET", api+prefix, nil)
	if err != nil {
		panic(err)
	}
	req.Header.Add("User-Agent", "mzap")

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
