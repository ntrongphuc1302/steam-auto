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
        [Parameter(Mandatory)][int]$SpeedTestBytes,
        $Weights
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

    # 5. Speed: tiny download to measure Mbps. Best-effort; if the CDN
    # is slow or unreachable the profile still gets a Score=0 for speed.
    $tmp = $null
    try {
        $tmp = Join-Path $env:TEMP "steam-auto-speed-$($Profile.Name).bin"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-WebRequest -Uri $script:CdnSpeedUrl -OutFile $tmp -TimeoutSec 10 -UseBasicParsing -ErrorAction SilentlyContinue | Out-Null
        $sw.Stop()
        if ((Test-Path $tmp) -and $sw.ElapsedMilliseconds -gt 0) {
            $size = (Get-Item $tmp).Length
            if ($size -gt 0) {
                $bits = $size * 8
                $kbps = [int]($bits / $sw.ElapsedMilliseconds)
                $result.SpeedKbps = $kbps
            }
        }
    } catch { }
    finally {
        if ($tmp -and (Test-Path $tmp)) {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    # 6. Cleanliness: success status and not redirected to captive portal.
    $result.Clean = ($result.HttpsCode -ge 200 -and $result.HttpsCode -lt 400)

    # 7. Score (out of 100). Use the orchestrator's weights if supplied
    # via config; otherwise fall back to the built-in defaults.
    $result.Score = Compute-ProfileScore -Result $result -SpeedTestBytes $SpeedTestBytes -Weights $Weights
    return $result
}

function Compute-ProfileScore {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][int]$SpeedTestBytes,
        $Weights
    )

    # If the caller passed weights, honour them; otherwise use defaults.
    if ($Weights) {
        $wLat  = if ($Weights.PSObject.Properties['Latency']) { $Weights.Latency } else { 30 }
        $wTcp  = if ($Weights.PSObject.Properties['Tcp'])     { $Weights.Tcp }     else { 25 }
        $wHttp = if ($Weights.PSObject.Properties['Https'])   { $Weights.Https }   else { 15 }
        $wSpd  = if ($Weights.PSObject.Properties['Speed'])   { $Weights.Speed }   else { 20 }
        $wCln  = if ($Weights.PSObject.Properties['Clean'])   { $Weights.Clean }   else { 10 }
    } else {
        $wLat, $wTcp, $wHttp, $wSpd, $wCln = 30, 25, 15, 20, 10
    }

    # Latency: < 30ms = full points, > 500ms = 0, linear in between.
    $lat = if ($Result.LatencyMs -le 0) { 0 }
           elseif ($Result.LatencyMs -le 30) { $wLat }
           elseif ($Result.LatencyMs -ge 500) { 0 }
           else { [int]($wLat * (1 - (($Result.LatencyMs - 30) / 470))) }

    # TCP: binary.
    $tcp = if ($Result.TcpOk) { $wTcp } else { 0 }

    # HTTPS: 2xx/3xx = full, 4xx = partial, others = 0.
    $https = switch ($Result.HttpsCode) {
        { $_ -ge 200 -and $_ -lt 400 } { $wHttp }
        { $_ -ge 400 -and $_ -lt 500 } { [int]($wHttp / 3) }
        default { 0 }
    }

    # Speed: cap at 10 Mbps = full points.
    $speedCap = 10240
    $speed = if ($Result.SpeedKbps -le 0) { 0 }
             elseif ($Result.SpeedKbps -ge $speedCap) { $wSpd }
             else { [int]($wSpd * ($Result.SpeedKbps / $speedCap)) }

    # Clean: binary.
    $clean = if ($Result.Clean) { $wCln } else { 0 }

    return ($lat + $tcp + $https + $speed + $clean)
}

# Forward declaration so Prober can ask Applier to set DNS.
function Set-ProfileDns { throw 'Set-ProfileDns must be defined by Applier.ps1' }