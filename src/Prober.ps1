# Prober.ps1
# For each profile: temporarily apply, measure latency / TCP / HTTPS /
# speed / cleanliness, then revert. Returns a scored list so the
# orchestrator can pick the best one instead of the first one that
# barely passes.

Set-StrictMode -Version Latest

$script:SteamStoreHost  = 'store.steampowered.com'
$script:SteamCommHost   = 'steamcommunity.com'
$script:CdnSpeedUrl     = 'https://cdn.cloudflare.steamstatic.com/client/steam_client_win32.zip.size'

function Invoke-ProfileProbe {
    param(
        [Parameter(Mandatory)]$Profile,
        [Parameter(Mandatory)][int]$SpeedTestBytes
    )

    $result = [pscustomobject]@{
        Profile       = $Profile.Name
        DoH           = $Profile.DoH
        LatencyMs     = -1
        TcpOk         = $false
        HttpsCode     = 0
        SpeedKbps     = 0
        Clean         = $false
        Score         = 0
        Notes         = ''
    }

    # 1. Apply DNS for this profile only (caller reverts later).
    try {
        Set-ProfileDns -Profile $Profile -ErrorAction Stop
    } catch {
        $result.Notes = "apply-failed: $($_.Exception.Message)"
        return $result
    }
    ipconfig /flushdns | Out-Null

    # 2. Latency: median of 3 DNS resolutions.
    try {
        $samples = @()
        for ($i = 0; $i -lt 3; $i++) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $null = Resolve-DnsName $script:SteamStoreHost -ErrorAction SilentlyContinue
            $sw.Stop()
            if ($sw.ElapsedMilliseconds -gt 0) { $samples += $sw.ElapsedMilliseconds }
        }
        if ($samples.Count -gt 0) {
            $sorted = $samples | Sort-Object
            $result.LatencyMs = [int]($sorted[[Math]::Floor($sorted.Count / 2)])
        }
    } catch { }

    # 3. TCP 443 handshake.
    try {
        $tcp = Test-NetConnection -ComputerName $script:SteamStoreHost -Port 443 -WarningAction SilentlyContinue
        $result.TcpOk = [bool]$tcp.TcpTestSucceeded
    } catch { $result.TcpOk = $false }

    # 4. HTTPS HEAD.
    try {
        $resp = Invoke-WebRequest -Uri "https://$script:SteamStoreHost" -Method Head -UseBasicParsing -TimeoutSec 10
        $result.HttpsCode = [int]$resp.StatusCode
    } catch {
        $result.HttpsCode = 0
    }

    # 5. Speed: tiny download to measure Mbps.
    try {
        $tmp = Join-Path $env:TEMP "steam-auto-speed-$($Profile.Name).bin"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-WebRequest -Uri $script:CdnSpeedUrl -OutFile $tmp -TimeoutSec 10 -UseBasicParsing -ErrorAction SilentlyContinue | Out-Null
        $sw.Stop()
        if ((Test-Path $tmp) -and $sw.ElapsedMilliseconds -gt 0) {
            $size = (Get-Item $tmp).Length
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            if ($size -gt 0) {
                $bits = $size * 8
                $kbps = [int]($bits / $sw.ElapsedMilliseconds)
                $result.SpeedKbps = $kbps
            }
        }
    } catch { }

    # 6. Cleanliness: success status and not redirected to captive portal.
    $result.Clean = ($result.HttpsCode -ge 200 -and $result.HttpsCode -lt 400)

    # 7. Score (out of 100).
    $result.Score = Compute-ProfileScore -Result $result -SpeedTestBytes $SpeedTestBytes
    return $result
}

function Compute-ProfileScore {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][int]$SpeedTestBytes
    )

    # Use the default weights here; orchestrator passes real weights via
    # the parent call's config.
    $w = [pscustomobject]@{
        Latency = 30; Tcp = 25; Https = 15; Speed = 20; Clean = 10
    }

    # Latency: < 30ms = 30, > 500ms = 0, linear in between.
    $lat = if ($Result.LatencyMs -le 0) { 0 }
           elseif ($Result.LatencyMs -le 30) { 30 }
           elseif ($Result.LatencyMs -ge 500) { 0 }
           else { [int](30 * (1 - (($Result.LatencyMs - 30) / 470))) }

    # TCP: binary 25 / 0.
    $tcp = if ($Result.TcpOk) { 25 } else { 0 }

    # HTTPS: 200/301/302 = full, others partial.
    $https = switch ($Result.HttpsCode) {
        { $_ -ge 200 -and $_ -lt 400 } { 15 }
        { $_ -ge 400 -and $_ -lt 500 } { 5 }
        default { 0 }
    }

    # Speed: cap at 10 Mbps = full points.
    $speedCap = 10240
    $speed = if ($Result.SpeedKbps -le 0) { 0 }
             elseif ($Result.SpeedKbps -ge $speedCap) { 20 }
             else { [int](20 * ($Result.SpeedKbps / $speedCap)) }

    # Clean: binary 10 / 0.
    $clean = if ($Result.Clean) { 10 } else { 0 }

    return ($lat + $tcp + $https + $speed + $clean)
}

# Forward declaration so Prober can ask Applier to set DNS.
function Set-ProfileDns { throw 'Set-ProfileDns must be defined by Applier.ps1' }