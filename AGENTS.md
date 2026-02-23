# AGENTS Guide for mzap

## Purpose
- `mzap` is a Crystal CLI for multi-target OWASP ZAP scanning.
- It dispatches targets across one or more ZAP API hosts, supports optional wait mode, and can export reports.

## Tech Stack
- Language: Crystal (`>= 1.19.1`)
- Package manager: `shards`
- Entry binary target: `src/mzap_cli.cr`
- CI baseline Crystal version: `1.19.1`

## Repository Map
- `src/mzap_cli.cr`
  - Process entrypoint (`Mzap::CLI.run(ARGV)`).
- `src/mzap/cli.cr`
  - Global option parsing, command routing, validation, help text.
- `src/mzap/client.cr`
  - HTTP calls to ZAP, round-robin host selection, wait/poll logic, report generation, stop endpoints.
- `src/mzap/options.cr`
  - Runtime options model (`wait`, `report`, intervals, timeout).
- `src/mzap/reporter.cr`
  - Output formatting (`INFO` to stdout, `WARN` to stderr).
- `src/mzap/config.cr`
  - Optional config-file notice (`~/.mzap*`).
- `spec/mzap_client_scan_spec.cr`
  - Scan dispatch behavior and request/header checks.
- `spec/mzap_client_wait_spec.cr`
  - Wait/poll lifecycle, status parsing, timeout paths.
- `spec/mzap_client_report_spec.cr`
  - Report generation, output path resolution, fallback behavior.
- `spec/mzap_client_stop_spec.cr`
  - Stop endpoints and stop-summary behavior.
- `spec/mzap_cli_*.cr`, `spec/mzap_config_*.cr`
  - CLI routing/validation and config discovery/parsing coverage.
- `spec/support/test_helpers.cr`
  - Shared `TestServer` and test helper utilities.
- `github-action/` + `action.yml`
  - Docker-based GitHub Action wrapper for CLI execution.

## Core Commands
- Install deps:
  - `shards install --frozen`
- Build release binary:
  - `crystal build --release src/mzap_cli.cr -o bin/mzap`
- Run tests:
  - `crystal spec`
- Run CLI locally:
  - `crystal run src/mzap_cli.cr -- version`
  - `crystal run src/mzap_cli.cr -- spider --urls samples/target.txt --apis http://localhost:8090`

## Agent Workflow
1. Read affected files in `src/mzap/` and matching specs in `spec/mzap_*_spec.cr`.
2. Implement changes with minimal scope.
3. Add/update tests for behavior changes.
4. Run `crystal spec` and, when relevant, release build command.
5. Update `README.md` and help text when CLI behavior or flags change.

## Change Rules
- CLI flags:
  - Keep `GlobalOptions`, `parse_global_options`, and `HELP_TEXT` in sync.
  - Validate flags in `CLI.run` and cover new validation in specs.
- Scan behavior:
  - Keep round-robin API host dispatch unless intentionally changed.
  - Preserve API key header behavior (`X-ZAP-API-Key`).
  - For new scan types, add API constants, dispatch path, wait status handling, and tests.
- Wait/report behavior:
  - `--wait` and report options are scan-command only (`spider`, `ajaxspider`, `ascan`).
  - Keep timeout semantics (`0` means no timeout).
- Output behavior:
  - Reporter output format is part of contract; avoid unnecessary format changes.

## Testing Notes
- Reuse `TestServer` pattern in `spec/support/test_helpers.cr`.
- Assert:
  - Request path and query params.
  - Header propagation (`X-ZAP-API-Key`).
  - Non-2xx error paths.
  - Wait completion and timeout cases when touching polling logic.
  - Report generation endpoint and fallback behavior.

## CI and Release Notes
- Workflows:
  - Crystal build/test: `.github/workflows/crystal.yml`
  - Docker image build smoke tests: `.github/workflows/docker-image.yml`
  - Docker publish: `.github/workflows/docker-publish.yml`
- Keep Crystal version aligned across:
  - `shard.yml`
  - `Dockerfile`
  - `github-action/Dockerfile`
  - CI workflow env
- Version string currently lives in `src/mzap/version.cr`; update references consistently for releases.

## Quick PR Checklist
- [ ] `crystal spec` passes.
- [ ] Build command passes when code path changed significantly.
- [ ] Specs added/updated for behavior changes.
- [ ] CLI help and README updated when flags/usage changed.
- [ ] No breaking change to GitHub Action output contract (`GITHUB_OUTPUT` block in entrypoint).
