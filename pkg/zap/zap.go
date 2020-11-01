package zap

import (
	"bufio"
	log "github.com/sirupsen/logrus"
	"net/http"
	"os"
	"strings"
	"sync"
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

// SpiderAPI is api for add scan
const SpiderAPI = "/JSON/spider/action/scan/"

// AScanAPI is api for add scan
const AScanAPI = "/JSON/ascan/action/scan/"

// AjaxSpiderAPI is api for add scan
const AjaxSpiderAPI = "/JSON/ajaxSpider/action/scan/"

// Run is running app
func Run(urls, apis, prefix string, options OptionsZAP) {
	log.WithFields(log.Fields{
		"Size of Target": len(urls),
		"Prefix":         prefix,
	}).Info("Start")

	var wg sync.WaitGroup
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

	urlChan := make(chan string)
	arrayAPIs := strings.Split(apis, ",")
	for _, api := range arrayAPIs {
		wg.Add(1)
		go func() {
			for target := range urlChan {
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
				resp, err := client.Do(req)

				log.WithFields(log.Fields{
					"Target":  target,
					"ZAP API": api,
				}).Info("Added")

				if err != nil {
					//panic(err)
				}
				defer resp.Body.Close()
			}
			wg.Done()
		}()
	}
	for _, v := range arrayUrls {
		urlChan <- v
	}
	close(urlChan)
	wg.Wait()
}
