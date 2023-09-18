package zap

import (
	"bufio"
	"net/http"
	"os"
	"strings"

	logger "github.com/hahwul/volt/logger"
	"github.com/sirupsen/logrus"
)

// ZapObject is object for zap api
type ZapObject struct {
	URL         string
	maxChildren int
	Recurse     string
	inScope     bool
	contextName string
	subtreeOnly bool
}

// AccessAPI is api for access url
const AccessAPI = "/JSON/core/action/accessUrl"

// SpiderAPI is api for add scan
const SpiderAPI = "/JSON/spider/action/scan/"

// AScanAPI is api for add scan
const AScanAPI = "/JSON/ascan/action/scan/"

// AjaxSpiderAPI is api for add scan
const AjaxSpiderAPI = "/JSON/ajaxSpider/action/scan/"

func callAPI(target, urls, api, prefix string, options OptionsZAP) error {
	req, err := http.NewRequest("GET", api+prefix, nil)
	if err != nil {
		panic(err)
	}
	q := req.URL.Query()
	q.Add("url", target)
	req.URL.RawQuery = q.Encode()
	if options.APIKey != "" {
		req.Header.Add("X-ZAP-API-Key", options.APIKey)
	}

	client := &http.Client{}
	_, err = client.Do(req)
	return err
}

// Run is running app
func Run(urls, apis, prefix string, options OptionsZAP) {
	var scanType string
	switch prefix {
	case SpiderAPI:
		scanType = "spider"
	case AScanAPI:
		scanType = "active-scan"
	case AjaxSpiderAPI:
		scanType = "ajax-spider"
	}
	log := logger.GetLogger(false).WithField("type", scanType)
	log.Info("start")

	//var wg sync.WaitGroup
	var arrayUrls []string

	fo, err := os.Open(urls)
	if err != nil {
		panic(err)
	}
	defer fo.Close()

	reader := bufio.NewReader(fo)
	for {
		line, isPrefix, err := reader.ReadLine()
		if isPrefix || err != nil {
			break
		}
		arrayUrls = append(arrayUrls, string(line))
	}

	//urlChan := make(chan string)
	arrayAPIs := strings.Split(apis, ",")
	count := 0

	for _, target := range arrayUrls {
		var api = arrayAPIs[count]
		err = callAPI(target, urls, api, AccessAPI, options)
		if err != nil {
			log.WithFields(logrus.Fields{
				"data2": target,
				"data1": api,
			}).Warn("error (access)")
		}

		err = callAPI(target, urls, api, prefix, options)
		if err != nil {
			log.WithFields(logrus.Fields{
				"data2": target,
				"data1": api,
			}).Warn("error (scan)")
		} else {
			log.WithFields(logrus.Fields{
				"data2": target,
				"data1": api,
			}).Info("added")
		}

		if len(arrayAPIs)-1 > count {
			count = count + 1
		} else {
			count = 0
		}

	}
}
