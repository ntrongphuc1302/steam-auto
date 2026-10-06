# steam-auto

A zero-friction auto-unblocker for Steam on Windows. Detects when Steam
is being blocked, picks the best DNS profile (not the first that
"passes"), applies it, verifies it worked, rolls back if not. A
watchdog keeps it healthy in the background, even across reboots.

## Quick start

```cmd
git clone https://github.com/ntrongphuc1302/steam-auto.git
cd steam-auto\bin
install.bat
```

That's it. `install.bat` registers a Windows Task named `SteamAuto`
that runs at every boot, runs once immediately, and then keeps a
background watchdog on. To remove:

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
|-- bin/
|   |-- install.bat          # one-shot installer
|   |-- uninstall.bat        # removes the scheduled task + restores DNS
|   |-- steam-auto.bat       # manual launcher
|   `-- steam-auto.ps1       # orchestrator (PowerShell)
|-- src/                     # library files, dot-sourced by the orchestrator
|   |-- Config.ps1
|   |-- Logger.ps1
|   |-- State.ps1
|   |-- Profiles.ps1
|   |-- Prober.ps1
|   |-- Detect.ps1
|   |-- Applier.ps1
|   |-- Rollback.ps1
|   |-- Cache.ps1
|   `-- Watchdog.ps1
|-- config/
|   `-- config.psd1          # user-tunable defaults
|-- docs/                    # screenshots, diagrams (empty for now)
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