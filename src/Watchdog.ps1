# Watchdog.ps1
# Loops forever (or until self-restart window expires). Each tick:
#  - Test Steam reachability
#  - If failing, re-run orchestrator
#  - If passing, gradually widen the polling interval
# Adaptive polling means a healthy Steam gets probed once an hour, not
# once every 5 minutes - ideal for long sessions.

Set-StrictMode -Version Latest

function Get-NextInterval {
    param([int]$ConsecutiveOk)

    switch ($ConsecutiveOk) {
        0       { return 60    }   # Fast
        1       { return 300   }   # Steady
        2       { return 900   }   # Stable
        3       { return 1800  }   # Rock-solid
        default { return 3600  }   # Sleep
    }
}

function Start-Watchdog {
    param(
        [Parameter(Mandatory)][int]$SelfRestartHours,
        [Parameter(Mandatory)][scriptblock]$OnTick
    )

    $start = Get-Date
    $consecutiveOk = 0

    while ($true) {
        # Self-restart: clean exit so Task Scheduler can relaunch us.
        if ((New-TimeSpan -Start $start -End (Get-Date)).TotalHours -ge $SelfRestartHours) {
            Write-Log -Level INFO "Self-restart window reached, exiting cleanly"
            return
        }

        try {
            $steamOk = & $OnTick
        } catch {
            $steamOk = $false
            Write-Log -Level ERROR "Tick failed: $($_.Exception.Message)"
        }

        if ($steamOk) {
            $consecutiveOk++
        } else {
            $consecutiveOk = 0
        }

        $interval = Get-NextInterval -ConsecutiveOk $consecutiveOk
        # Sleep in 1s slices so a stop request is responsive.
        $deadline = (Get-Date).AddSeconds($interval)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 1
        }
    }
}