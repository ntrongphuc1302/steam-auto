# steam-auto

A zero-friction auto-unblocker for Steam on Windows. Detects when Steam
is being blocked, picks the best DNS profile (not the first that
"passes"), applies it, verifies it worked, rolls back if not. A
watchdog keeps it healthy in the background, even across reboots.

## Quick start

```cmd
git clone https://github.com/ntrongphuc1302/steam-auto.git
cd steam-auto
install.bat
```

That's it. `install.bat` runs the full test suite (it must all pass),
then registers a Windows Task named `SteamAuto` that runs at every
boot, runs once immediately, and then keeps a background watchdog on.
To remove:

```cmd
uninstall.bat
```

## How it works

```
                +-----------------+
                | Detect (none?)  |
                +--------+--------+
                         | no
                         v
                +-----------------+
                | Probe profiles  |   (Cloudflare, Google, DoH variants, ...)
                +--------+--------+
                         v
                +-----------------+
                | Pick best score |
                +--------+--------+
                         v
                +-----------------+
                | Apply + warm    |
                +--------+--------+
                         v
                +-----------------+
                | Verify (30s)    |----+
                +--------+--------+    |
                         | ok          | fail
                         v             v
                    Done       Restore pre-tick DNS
```

## Adaptive watchdog

The watchdog polls Steam on a sliding schedule. After each
successful probe the interval grows:

| Consecutive OK | Interval |
|----------------|----------|
| 0 (last failed) | 1 minute  |
| 1               | 5 minutes |
| 2               | 15 minutes |
| 3               | 30 minutes |
| 4+              | 1 hour    |

A failure resets the counter to zero. The watchdog also self-restarts
every 6 hours (configurable) so any memory leak from a long session
is wiped by a clean relaunch.

## Profiles

| Profile        | DNS                | DoH |
|----------------|--------------------|-----|
| Cloudflare     | 1.1.1.1, 1.0.0.1   | no  |
| Google         | 8.8.8.8, 8.8.4.4   | no  |
| CloudflareDoH  | 1.1.1.1            | yes |
| GoogleDoH      | 8.8.8.8            | yes |
| Quad9          | 9.9.9.9            | no  |

## Repo layout

```
steam-auto/
|-- install.bat             # one-shot: tests + install (admin UAC, root)
|-- uninstall.bat           # one-shot: restore + remove task (admin UAC, root)
|-- bin/
|   |-- install.bat          # internal: snapshot DNS, register task
|   |-- uninstall.bat        # internal: restore DNS, delete task
|   |-- steam-auto.bat       # manual launcher
|   `-- steam-auto.ps1       # orchestrator (PowerShell)
|-- src/                     # library files, dot-sourced by the orchestrator
|   |-- Config.ps1           # config loader + validator
|   |-- Logger.ps1           # file + console logging
|   |-- State.ps1            # atomic state persistence
|   |-- Profiles.ps1         # the 5 DNS profiles
|   |-- Prober.ps1           # score each profile
|   |-- Detect.ps1           # block-kind classifier
|   |-- Applier.ps1          # actually set DNS / DoH
|   |-- Rollback.ps1         # restore from snapshot
|   |-- Cache.ps1            # warm the resolver cache
|   `-- Watchdog.ps1         # adaptive polling loop
|-- config/
|   `-- config.psd1          # user-tunable defaults
|-- tests/                   # 18 hermetic tests (run sandbox-safe)
|   |-- run-all.ps1          # one-shot runner
|   `-- test-*.ps1
|-- logs/                    # runtime logs (gitignored)
|-- state/                   # runtime state (gitignored)
|-- .gitignore
`-- README.md
```

## Configuration

Edit `config\config.psd1` to tune the polling intervals, profile
order, or scoring weights. The file is a plain PowerShell data file.
If the file is invalid or missing, sensible defaults are used.

## Logs

`logs\steam-auto-YYYY-MM-DD.log` keeps a daily record. Only meaningful
events are logged (failures, profile changes, rollbacks) unless
`LogVerbose = $true` in the config.

## Testing

Hermetic unit tests live in `tests\`. The full suite runs in any
PowerShell 5.1 session (no admin required):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1
```

There are three runner scripts to choose from:

| Script | Needs admin? | Logs to? |
|--------|--------------|-----------|
| `install.bat` (root) | yes (UAC) | `tests\test-results.log` |
| `tests\run-all.ps1` | no | stdout only |

The root `install.bat` self-elevates and runs the E2E test
(`test-08-e2e-rollback.ps1`) which actually mutates DNS; it only
installs the scheduled service after the full suite is green.

The `tests\run-all.ps1` runner is non-admin by default and skips
the E2E test when called from a sandbox; the E2E test runs whenever
the caller is elevated (and skips itself otherwise).

After any batch runner finishes, the log opens automatically. The
final exit code is also written to `tests\test-exit.txt` so you
can `type tests\test-exit.txt` later to check.

## Safety

- DNS changes are scoped to the user's network adapters; no system
  files are touched.
- Before applying anything the orchestrator snapshots the current
  DNS state and restores it on failure.
- `uninstall.bat` always restores the pre-install DNS, falling back
  to DHCP if the snapshot is unavailable.

## Requirements

- Windows 10 or newer
- Administrator privileges (only needed for install / uninstall)
- No external dependencies. PowerShell ships with Windows.

## License

MIT.