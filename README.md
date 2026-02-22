<h1 align="center">
  <br>
  <a href=""><img src="https://user-images.githubusercontent.com/13212227/90962250-b72e5000-e4e9-11ea-8c42-75e9d0d799be.jpg" width="100%"></a>
  <br>
  <a href=""><img src="https://img.shields.io/badge/contributions-welcome-brightgreen.svg?style=flat"></a>
  <img src="https://img.shields.io/github/v/release/hahwul/mzap?style=flat"> 
  <a href="https://goreportcard.com/report/github.com/hahwul/mzap"><img src="https://goreportcard.com/badge/github.com/hahwul/mzap"></a>
  <a href="https://twitter.com/intent/follow?screen_name=hahwul"><img src="https://img.shields.io/twitter/follow/hahwul?style=flat&logo=twitter"></a>
</h1>
⚡️ Multiple target ZAP Scanning / mzap is a tool for scanning N*N in ZAP.

## Concept
![1414](https://user-images.githubusercontent.com/13212227/90961636-4a18bb80-e4e5-11ea-9913-a573fe748ce4.png)

## Installation
### go
```
go install github.com/hahwul/mzap@latest
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

Subcommands:
  ajaxspider  Start Ajax Spider scans in ZAP
  ascan       Start Active Scan jobs in ZAP
  help        Show help for a command
  spider      Start Spider scans in ZAP
  stop        Stop running scans
  version     Show mzap version

Flags:
      --apikey string        ZAP API key (omit when API key auth is disabled)
      --apis string          Comma-separated ZAP API host URLs
                             e.g. --apis http://localhost:8090,http://192.168.0.4:8090 (default "http://localhost:8090")
      --config string        Config file path (TOML supported; default: $HOME/.config/mzap/config.toml)
      --report-format        Report format after scan completion (html/pdf)
      --report-out           Report output path (default: mzap-report-<timestamp>.<ext>)
      --wait                 Wait for initiated scans to complete
      --wait-interval        Poll interval in seconds while waiting (default 2)
      --wait-timeout         Wait timeout in seconds (default 0: no timeout)
      -h, --help             Show help for mzap
      --urls string          Path to URL list file (e.g. --urls hosts.txt)
```

`mzap` automatically loads config from `$HOME/.config/mzap/config.toml` when present.
CLI flags override values from config.

```toml
[mzap]
apis = ["http://localhost:8090", "http://192.168.0.4:8090"]
apikey = "your-zap-api-key"
urls = "samples/target.txt"
wait = true
wait_interval = 2
wait_timeout = 0
report_format = "html"
report_out = "reports/mzap.html"
```

```bash
# wait until spider scan is complete, then export report
mzap spider --urls sample/target.txt --apis http://localhost:8090 --wait --report-format html --report-out reports/mzap.html
```

```
$ mzap spider --urls sample/target.txt --apis

          ,/
        ,'/
      ,' /
    ,'  /_____,
  .'____    ,'                     MZAP
        /  ,'     [ Multiple target/agent ZAP scanning ]
       / ,'       [ v1.3.1 ] [ by @hahwul ]
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

### Github action
```yaml
- name: MZAP Env
  uses: hahwul/mzap@v1.3.1-action
  with:
    arguments: 'spider --urls sample/target.txt --apis'
```
