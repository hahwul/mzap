# mzap

`mzap` is a Crystal CLI for multi-target [ZAP](https://www.zaproxy.org) scanning.
It dispatches targets across one or more ZAP API hosts, supports optional wait mode, and can export reports.

## Features

- Scan commands: `spider`, `ajaxspider`, `clientspider` (ZAP 2.16+), `ascan`, `pscan`
- API definition import for `openapi`, `soap`, `graphql`, and `postman`
- Sites Tree `export`/`prune` for ZAP 2.16+ differential/incremental scanning
- Scan policy discovery (`policies`)
- Multi-host dispatch with round-robin scheduling
- Optional wait/poll mode with timeout support
- Report export (`html`/`pdf`/`json`/`md`/`sarif`) with fallback behavior
- `--fail-on` risk gate for CI exit codes
- Stop commands for `spider`, `ajaxspider`, `clientspider`, `ascan`, or `all`
- Optional config loading from `$HOME/.config/mzap/config.toml` and legacy paths

## Requirements

- Crystal `>= 1.19.1`
- A running ZAP API endpoint (or endpoints)

## Installation

### Homebrew

```bash
brew install hahwul/mzap/mzap
```

### Build From Source

```bash
shards install --frozen
crystal build --release src/mzap_cli.cr -o bin/mzap
```

### Run Without Building

```bash
crystal run src/mzap_cli.cr -- version
```

### Docker Image

```bash
docker build -t mzap .
docker run --rm -v "$PWD:/work" mzap spider --urls /work/samples/target.txt --apis http://host.docker.internal:8090
```

## Usage

```text
Usage:
  mzap [command]

Subcommands:
  ajaxspider    Start Ajax Spider scans in ZAP
  ascan         Start Active Scan jobs in ZAP
  clientspider  Start Client Spider scans in ZAP (ZAP 2.16+)
  help          Show help for a command
  import        Import API definitions (openapi/soap/graphql/postman)
  policies      List active-scan policies in ZAP
  pscan         Wait for Passive Scan completion in ZAP
  sitestree     Export or prune the ZAP Sites Tree (ZAP 2.16+)
  spider        Start Spider scans in ZAP
  stop          Stop running scans
  version       Show mzap version

Flags:
  --apikey string        ZAP API key (omit when API key auth is disabled)
  --apis string          Comma-separated ZAP API host URLs
                         e.g. --apis http://localhost:8090,http://192.168.0.4:8090 (default "http://localhost:8090")
  --config string        Config file path (TOML supported; default: $HOME/.config/mzap/config.toml)
  --context string       ZAP context file to import before scanning
  --fail-on string       Fail with exit code 1 if alerts at or above risk level
  --format string        API definition format for import (openapi/soap/graphql/postman)
  --target-url string    Target/endpoint URL override for import
  --policy string        Scan policy name for active scan
  --report-format        Report format after scan completion (html/pdf/json/md/sarif)
  --report-out           Report output path (default: mzap-report-<timestamp>.<ext>)
  --concurrency          Number of parallel scan dispatches (default 1)
  --wait                 Wait for initiated scans to complete
  --wait-interval        Poll interval in seconds while waiting (default 2)
  --wait-timeout         Wait timeout in seconds (default 0: no timeout)
  -h, --help             Show help for mzap
  --urls string          Path to URL list file (e.g. --urls hosts.txt)
```

Run `mzap help <command>` for command-specific flags.

## Examples

```bash
# spider scan with two ZAP API hosts
mzap spider --urls samples/target.txt --apis http://localhost:8090,http://192.168.0.4:8090

# run scan, wait for completion, and generate an HTML report
mzap spider --urls samples/target.txt --apis http://localhost:8090 --wait --report-format html --report-out reports/mzap.html

# Client Spider (browser-based crawler, ZAP 2.16+; needs the Client Side Integration add-on)
mzap clientspider --urls samples/target.txt --apis http://localhost:8090 --wait

# import an OpenAPI definition, wait for passive scan, gate CI on high-risk alerts
mzap import --format openapi --urls samples/specs.txt --target-url https://api.example.com \
  --apis http://localhost:8090 --wait --report-format sarif --fail-on high

# import API specs from stdin
echo https://api.example.com/openapi.json | mzap import --format openapi --urls -

# discover available scan policies (then use one with `ascan --policy`)
mzap policies --apis http://localhost:8090

# Sites Tree baseline for differential scanning (path resolved by the ZAP daemon)
mzap sitestree export baseline.tree --apis http://localhost:8090
mzap sitestree prune baseline.tree --apis http://localhost:8090

# stop all running scan types
mzap stop all --apis http://localhost:8090
```

> **Importing APIs:** `mzap import` seeds ZAP's Sites Tree and lets passive
> scanning run; to actively scan the imported endpoints afterwards, run
> `mzap ascan` against the same target(s). For local files, paths in `--urls`
> (and `--target-url`) are resolved by the ZAP daemon, so mount them into the
> container when ZAP runs in Docker.

## Config

`mzap` automatically loads config when present.
Priority is:

1. Explicit `--config` path (if it exists)
2. `$HOME/.config/mzap/config.toml`
3. `$HOME/.config/mzap/config` + extension variants
4. `$HOME/.mzap` + extension variants

CLI flags always override config values.

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

## GitHub Action

This repository includes a Docker-based GitHub Action (`action.yml`).

```yaml
- name: Run mzap
  uses: hahwul/mzap@<tag>
  with:
    arguments: "spider --urls samples/target.txt --apis http://localhost:8090"
```

## Development

```bash
# tests
crystal spec

# release build
crystal build --release src/mzap_cli.cr -o bin/mzap
```
