# Detect.ps1
# Tells the orchestrator whether Steam is currently reachable, and if
# not, which kind of blocking we are hitting. That way we can skip
# profiles that cannot possibly help.

Set-StrictMode -Version Latest

$script:SteamStoreHost = 'store.steampowered.com'
$script:SteamCommHost  = 'steamcommunity.com'

function Test-SteamReachable {
    # DNS resolve + TCP 443 = minimal reachability check.
    $dns = $false
    try {
        $null = Resolve-DnsName $script:SteamStoreHost -ErrorAction Stop
        $dns = $true
    } catch { $dns = $false }

    $tcp = $false
    try {
        $tcp = (Test-NetConnection -ComputerName $script:SteamStoreHost -Port 443 -WarningAction SilentlyContinue).TcpTestSucceeded
    } catch { $tcp = $false }

    return ($dns -and $tcp)
}

function Get-BlockKind {
    # Returns: 'none', 'dns', 'ip', 'dpi'.
    $dns = $false
    try {
        $null = Resolve-DnsName $script:SteamStoreHost -ErrorAction Stop
        $dns = $true
    } catch { }

    $tcp = $false
    try {
        $tcp = (Test-NetConnection -ComputerName $script:SteamStoreHost -Port 443 -WarningAction SilentlyContinue).TcpTestSucceeded
    } catch { }

    if ($dns -and $tcp) { return 'none' }
    if (-not $dns)      { return 'dns' }
    if (-not $tcp)      { return 'ip' }   # DNS works but IP/port blocked -> DPI/SNI filter.
    return 'unknown'
}

function Test-CaptivePortalRedirect {
    param([Parameter(Mandatory)][int]$ExpectedCode = 200)

    try {
        $resp = Invoke-WebRequest -Uri "https://$script:SteamStoreHost" -Method Head -UseBasicParsing -TimeoutSec 10
        $finalUri = $resp.BaseResponse.ResponseUri.AbsoluteUri
        if ($finalUri -notmatch "steampowered\.com$") { return $true }
        return ($resp.StatusCode -ne $ExpectedCode)
    } catch {
        # On many networks the redirect shows as exception with redirect URI
        # in the inner exception; conservative answer = false (we do not
        # treat connect failure as captive portal).
        return $false
    }
}