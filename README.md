<h1 align="center">
  <br>
  <a href=""><img src="https://user-images.githubusercontent.com/13212227/90962250-b72e5000-e4e9-11ea-8c42-75e9d0d799be.jpg" width="100%"></a>
  <br>
  MZAP
  <br>
  <img src="https://img.shields.io/github/v/release/hahwul/mzap?style=flat-square"> 
  <a href="https://snapcraft.io/mzap"><img src="https://snapcraft.io/mzap/badge.svg" /></a>
  <img src="https://img.shields.io/github/languages/top/hahwul/mzap?style=flat-square"> <img src="https://app.codacy.com/project/badge/Grade/6c7f7be26bed4673b65001153f004ddd"> <a href="https://goreportcard.com/report/github.com/hahwul/mzap"><img src="https://goreportcard.com/badge/github.com/hahwul/mzap"></a>
<a href="https://twitter.com/intent/follow?screen_name=hahwul"><img src="https://img.shields.io/twitter/follow/hahwul?style=flat-square"></a>
</h1>
⚡️ Multiple target ZAP Scanning / mzap is a tool for scanning N*N in ZAP.

## Concept
![1414](https://user-images.githubusercontent.com/13212227/90961636-4a18bb80-e4e5-11ea-9913-a573fe748ce4.png)

## Usage
```
Usage:
  mzap [command]

Available Commands:
  ajaxspider  Add AjaxSpider ZAP
  ascan       Add ActiveScan ZAP
  help        Help about any command
  spider      Add ZAP spider
  stop        Stop Scanning
  version     show version

Flags:
      --config string   config file (default is $HOME/.mzap.yaml)
  -h, --help            help for mzap
      --hosts string    ZAP API Host(s) address / e.g --hosts http://localhost:8090,http://192.168.0.4:8090 (default "http://localhost:8090")
      --urls string     URL list file / e.g --urls hosts.txt

Use "mzap [command] --help" for more information about a command.
```

```
$ mzap spider --urls sample/target.txt
INFO[0000] Start                                         Prefix=/JSON/spider/action/scan/ Size of Target=17
INFO[0000] Added                                         Target="http://testphp.vulnweb.com/" ZAP API="http://localhost:8090"
INFO[0000] Added                                         Target="http://www.hahwul.com" ZAP API="http://localhost:8090"
```

![1413](https://user-images.githubusercontent.com/13212227/90961424-dd50f180-e4e3-11ea-95cd-08b825a1eeed.png)
![1414](https://user-images.githubusercontent.com/13212227/90961367-4be17f80-e4e3-11ea-8d9f-68d8ba5d851f.png)
