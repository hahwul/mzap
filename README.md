<h1 align="center">
  <br>
  <a href=""><img src="https://user-images.githubusercontent.com/13212227/90962250-b72e5000-e4e9-11ea-8c42-75e9d0d799be.jpg" width="100%"></a>
  <br>
  <img src="https://img.shields.io/github/v/release/hahwul/mzap?style=flat"> 
  <a href="https://goreportcard.com/report/github.com/hahwul/mzap"><img src="https://goreportcard.com/badge/github.com/hahwul/mzap"></a>
  <a href="https://twitter.com/intent/follow?screen_name=hahwul"><img src="https://img.shields.io/twitter/follow/hahwul?style=flat&logo=twitter"></a>
</h1>
⚡️ Multiple target ZAP Scanning / mzap is a tool for scanning N*N in ZAP.

## Concept
![1414](https://user-images.githubusercontent.com/13212227/90961636-4a18bb80-e4e5-11ea-9913-a573fe748ce4.png)

## Installation
### go
go1.17
```
go install github.com/hahwul/mzap@latest
```

go1.16
```
GO111MODULE=on go get -u github.com/hahwul/mzap
```
### snapcraft
```
sudo snap install mzap
```
### homebrew
```
brew tap hahwul/mzap
brew install mzap
```

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
  version     Show version

Flags:
      --apikey string   ZAP API Key / if you disable apikey, not use this option
      --apis string     ZAP API Host(s) address
                        e.g --apis http://localhost:8090,http://192.168.0.4:8090 (default "http://localhost:8090")
      --config string   config file (default is $HOME/.mzap.yaml)
  -h, --help            help for mzap
      --urls string     URL list file / e.g --urls hosts.txt
```

```
$ mzap spider --urls sample/target.txt --apis

          ,/
        ,'/
      ,' /
    ,'  /_____,
  .'____    ,'                     MZAP
        /  ,'     [ Multiple target/agent ZAP scanning ]
       / ,'       [ v1.3.0 ] [ by @hahwul ]
      /,'
     /'

Jan 26 01:12:00.081 [INFO] [spider] start
Jan 26 01:12:00.088 [INFO] [spider] [http://localhost:8090] [http://testphp.vulnweb.com/] added
Jan 26 01:12:00.090 [INFO] [spider] [http://localhost:8090] [https://www.hahwul.com] added
Jan 26 01:12:00.092 [INFO] [spider] [http://localhost:8090] [https://owasp.org] added
Jan 26 01:12:00.095 [INFO] [spider] [http://localhost:8090] [https://www.zaproxy.org] added
Jan 26 01:12:00.098 [INFO] [spider] [http://localhost:8090] [https://portswigger.net] added
Jan 26 01:12:00.101 [INFO] [spider] [http://localhost:8090] [https://www.hackerone.com] added
Jan 26 01:12:00.103 [INFO] [spider] [http://localhost:8090] [https://www.bugcrowd.com] added
Jan 26 01:12:00.106 [INFO] [spider] [http://localhost:8090] [https://dalfox.hahwul.com] added
Jan 26 01:12:00.108 [INFO] [spider] [http://localhost:8090] [https://authz0.hahwul.com] added
```

![1413](https://user-images.githubusercontent.com/13212227/151013450-985ff38c-5bbf-4a58-b160-58dfebd0bf11.png)
![1414](https://user-images.githubusercontent.com/13212227/90961367-4be17f80-e4e3-11ea-8d9f-68d8ba5d851f.png)
