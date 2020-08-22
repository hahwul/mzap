package zap

import (
	"net/http"
	"strings"
	log "github.com/sirupsen/logrus"
	"bufio"
	"os"
	"sync"
)

type ZapObject struct {
	URL string
	maxChildren int
	Recurse string
	inScope bool
	contextName string
	subtreeOnly bool
}

const SpiderAPI = "/JSON/spider/action/scan/"
const AScanAPI = "/JSON/ascan/action/scan/"
const AjaxSpiderAPI = "/JSON/ajaxSpider/action/scan/"

// http://localhost:8090/JSON/spider/action/scan/?url=%&maxChildren=&recurse=&contextName=&subtreeOnly=
// http://localhost:8090/JSON/ascan/action/scan/?url=%&maxChildren=&recurse=&contextName=&subtreeOnly=
// http://localhost:8090/JSON/ajaxSpider/action/scan/?url=&inScope=&contextName=&subtreeOnly=
func Run(urls,apis,prefix string) {
	log.WithFields(log.Fields{
		"Size of Target": len(urls),
		"Prefix": prefix,
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
	for _ , api := range arrayAPIs {
		wg.Add(1)
		go func() {
			for target := range urlChan {
				req, err := http.NewRequest("GET", api+prefix, nil)
				if err != nil {
					panic(err)
				}
 				q := req.URL.Query()
				q.Add("url",target)
				req.URL.RawQuery = q.Encode()
				req.Header.Add("User-Agent", "mzap")
 
				client := &http.Client{}
				resp, err := client.Do(req)

				log.WithFields(log.Fields{
					"Target": target,
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
