# AGENTS Guide for mzap

## Purpose
`mzap` is a Crystal CLI (v2.0.0) for multi-target ZAP scanning. Dispatches targets across ZAP API hosts via round-robin, supports wait/poll mode, and exports reports.

## Tech Stack
- Crystal `>= 1.19.1` (CI baseline: `1.19.1`), no external dependencies (stdlib only)
- Package manager: `shards`, entry: `src/mzap_cli.cr`

## Repository Map

### Source (`src/mzap/`)
| File | Role |
|------|------|
| `cli.cr` | `GlobalOptions`/`ProvidedOptions` structs, command routing, flag parsing, validation, `HELP_TEXT` |
| `client.cr` | ZAP HTTP client — scan dispatch, round-robin, wait/poll, report generation (two-step fallback), stop endpoints |
| `options.cr` | `Options` struct (`api_key`, `urls`, `wait_for_completion`, `wait_interval_seconds`, `wait_timeout_seconds`, `report_format`, `report_out`) |
| `config.cr` | TOML config discovery & custom parser — priority: `--config` > `~/.config/mzap/config.toml` > `~/.mzap*` |
| `reporter.cr` | `[LEVEL] [type] [data] message` format — INFO→stdout, WARN→stderr |
| `banner.cr` | ASCII banner with version display |
| `version.cr` | `Mzap::VERSION` constant |

### Specs (`spec/`)
Naming convention: `mzap_<component>_<area>_spec.cr`. Uses in-process `TestServer` from `spec/support/test_helpers.cr`.

| File | Coverage |
|------|----------|
| `mzap_client_scan_spec.cr` | Scan dispatch, round-robin, headers, error paths |
| `mzap_client_wait_spec.cr` | Poll lifecycle, status parsing, timeout |
| `mzap_client_report_spec.cr` | Report generation, fallback, multi-host naming |
| `mzap_client_stop_spec.cr` | Stop endpoints |
| `mzap_cli_commands_spec.cr` | Command routing, validation errors |
| `mzap_cli_help_spec.cr` | Help text display |
| `mzap_cli_options_spec.cr` | Flag parsing (strings, ints, `=` syntax) |
| `mzap_config_discovery_spec.cr` | Config file discovery & priority |
| `mzap_config_parsing_spec.cr` | TOML parsing, arrays, types, error messages |
| `mzap_banner_spec.cr` | Banner output |
| `mzap_options_spec.cr` | Options struct |
| `mzap_reporter_spec.cr` | Reporter format |

### Other
- `github-action/` + `action.yml` — Docker-based GitHub Action (input: `arguments`, output: `output` via `GITHUB_OUTPUT`)
- `samples/target.txt` — Example target URLs

## Commands
```bash
shards install --frozen            # Install deps
crystal build --release src/mzap_cli.cr -o bin/mzap  # Build
crystal spec                       # Test
crystal run src/mzap_cli.cr -- <command> [flags]      # Run locally
```

## CLI Commands & Flags
**Commands:** `spider`, `ajaxspider`, `ascan`, `stop <mode>`, `version`, `help`

**Flags:** `--config`, `--urls`, `--apis` (default `http://localhost:8090`), `--apikey`, `--wait`, `--wait-interval`, `--wait-timeout`, `--report-format` (`html`|`pdf`), `--report-out`, `-h`

**Constraints:**
- `--wait`, `--report-*` are scan-command only (`spider`, `ajaxspider`, `ascan`)
- `--report-out` requires `--report-format`
- `--wait-interval > 0`, `--wait-timeout >= 0` (0 = no timeout)
- Config file values are overridden by CLI flags (`ProvidedOptions` tracks explicit flags)

## Key Behaviors
- **Round-robin dispatch**: targets distributed cyclically across `--apis` hosts
- **API key**: sent as `X-ZAP-API-Key` header (optional)
- **Scan flow**: ACCESS_API call → scan API call → track `ScanJob` (scan_id parsed from response)
- **Wait polling**: status checked via type-specific status API; complete at 100% or terminal state
- **Report fallback**: filtered report (with target `sites` param) → core report API if filtered fails
- **Config discovery**: TOML format, custom parser (no external lib), supports `[mzap]` section and string arrays

## Change Rules
- **CLI flags**: keep `GlobalOptions`, `ProvidedOptions`, `parse_global_options`, `apply_config_options`, and `HELP_TEXT` in sync
- **New scan types**: add API constants + dispatch path + wait status handling + tests in `client.cr`
- **Reporter format** is part of output contract — avoid unnecessary changes
- **Config parser**: supports TOML subset — extend carefully with tests in `mzap_config_parsing_spec.cr`

## Testing
- Reuse `TestServer` and helpers (`with_target_file`, `with_temp_home`) from `spec/support/test_helpers.cr`
- Assert: request path/query, `X-ZAP-API-Key` header, round-robin distribution, non-2xx errors, wait completion/timeout, report output paths and fallback

## CI & Version Alignment
- Workflows: `crystal.yml` (build/test), `docker-image.yml` (smoke test), `docker-publish.yml` (GHCR, multi-platform, cosign)
- Crystal version must stay aligned across: `shard.yml`, `Dockerfile`, `github-action/Dockerfile`, `.github/workflows/crystal.yml`
- Version string: `src/mzap/version.cr`

## PR Checklist
- [ ] `crystal spec` passes
- [ ] Release build passes if code path changed significantly
- [ ] Specs added/updated for behavior changes
- [ ] CLI help and README updated if flags/usage changed
- [ ] No breaking change to GitHub Action output contract (`GITHUB_OUTPUT`)
