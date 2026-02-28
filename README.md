# mzap

`mzap` is a Crystal CLI for multi-target OWASP ZAP scanning.
It dispatches targets across one or more ZAP API hosts, supports optional wait mode, and can export reports.

## Features

- Multiple scan commands: `spider`, `ajaxspider`, `ascan`
- Multi-host dispatch with round-robin scheduling
- Optional wait/poll mode with timeout support
- Report export (`html`/`pdf`) with fallback behavior
- Stop commands for `spider`, `ajaxspider`, `ascan`, or `all`
- Optional config loading from `$HOME/.config/mzap/config.toml` and legacy paths

## Requirements

- Crystal `>= 1.19.1`
- A running OWASP ZAP API endpoint (or endpoints)

## Installation

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

## Examples

```bash
# spider scan with two ZAP API hosts
mzap spider --urls samples/target.txt --apis http://localhost:8090,http://192.168.0.4:8090

# run scan, wait for completion, and generate an HTML report
mzap spider --urls samples/target.txt --apis http://localhost:8090 --wait --report-format html --report-out reports/mzap.html

# stop all running scan types
mzap stop all --apis http://localhost:8090
```

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
