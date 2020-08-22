package zap

import (
	"net/http"
	"strings"
	"fmt"
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
	fmt.Println(arrayAPIs)
	fmt.Println(arrayUrls)
	for _ , api := range arrayAPIs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for target := range urlChan {
				req, err := http.NewRequest("GET", api+prefix, nil)
				fmt.Println(req)
				if err != nil {
					panic(err)
				}
 				q := req.URL.Query()
				q.Add("url",target)
				req.URL.RawQuery = q.Encode()
				req.Header.Add("User-Agent", "mzap")
 
				client := &http.Client{}
				resp, err := client.Do(req)
				if err != nil {
					//panic(err)
				}
				defer resp.Body.Close()	
			}
		}()
	}
	for _, v := range arrayUrls {
		urlChan <- v
	}
	wg.Wait()
}
