# Tests — SteamAuto

This directory hosts the test suite. Each test is a standalone PowerShell script that exits with 0 on pass and non-zero on fail.

## Quick start

```cmd
cd tests
run-all.bat
```

`run-all.bat` calls `run-all.ps1`, which iterates over every `test-*.ps1` in lexical order, stops at the first non-zero exit, and writes a summary line.

`run-all.ps1` is also called automatically by the top-level `install.bat`, so a fresh clone can be installed end-to-end by double-clicking `install.bat` at the repo root.

## Test inventory

| File | What it checks | Requires admin |
|---|---|---|
| `test-01-import.ps1` | Every module in `src/` dot-sources without error | no |
| `test-02-config.ps1` | Defaults satisfy invariants (ProfilesOrder, intervals, sizes, weights sum to 100, types) | no |
| `test-03-profiles.ps1` | All five built-in profiles have DoH flag and IPv4 list | no |
| `test-04-score.ps1` | Scoring function returns expected ranges | no |
| `test-05-state.ps1` | Roundtrip via `state\state.json`, atomic write, `.tmp` leftover tolerated | no |
| `test-06-watchdog-interval.ps1` | `Get-NextInterval` boundaries (60s .. 3600s) | no |
| `test-07-detect-readonly.ps1` | `Test-SteamReachable` and `Get-BlockKind` return without throwing | no |
| `test-08b-applier-non-admin.ps1` | Non-admin path throws the admin-guard error | no (SKIP when admin) |
| `test-08-e2e-rollback.ps1` | Mutates real adapter DNS across 5 scenarios, restores baseline | **yes** |
| `test-09-cache-warmup.ps1` | `Invoke-DnsWarmup` exports + executes | no |
| `test-10-applier-helpers.ps1` | `Get-ActiveAdapters`, `Snapshot-CurrentDns`, legacy shape restore | no |
| `test-11-watchdog-tick.ps1` | `Invoke-WatchdogTick` swallows exceptions, returns OnTick's boolean | no |
| `test-12-rollback.ps1` | `Save-PreInstallSnapshot` writes valid JSON, DHCP fallback path | no |
| `test-13-logger.ps1` | `Initialize-Log` creates directory, `Write-Log` prefixes level | no |
| `test-14-profile-validation.ps1` | Validator rejects null / missing Name / empty IPv4 / bad IPs / empty template | no |
| `test-15-prober-custom-weights.ps1` | Score respects custom weights, HTTPS 4xx is partial | no |
| `test-16-config-validation.ps1` | Malformed `.psd1` falls back to defaults | no |
| `test-17-orchestrator-import.ps1` | Orchestrator file parses, references every key function, `-Install` runs | no |

`test-08-e2e-rollback.ps1` is the only test that mutates real adapter DNS. It always restores to baseline at the end, but you should not interrupt it mid-run.

## Output

Each run appends to `tests\test-results.log` and exits with 0 (all pass) or 1 (first failure). The summary line is `Result: <pass> passed, <fail> failed`.