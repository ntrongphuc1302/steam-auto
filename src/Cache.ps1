# Cache.ps1
# Pre-resolves the Steam endpoints into the local DNS resolver cache
# so the very first Steam connection after boot does not pay the full
# resolver latency cost.

Set-StrictMode -Version Latest

$script:WarmupHosts = @(
    'store.steampowered.com'
    'steamcommunity.com'
    'api.steampowered.com'
    'cdn.cloudflare.steamstatic.com'
    'client-update.akamai.steamstatic.com'
)

function Invoke-DnsWarmup {
    param([string]$RepoRoot)

    foreach ($host in $script:WarmupHosts) {
        try {
            $null = Resolve-DnsName $host -ErrorAction Stop
        } catch {
            # OK if one of them fails; cache warmup is best-effort.
        }
    }
    ipconfig /flushdns | Out-Null
    # Resolve again so entries land in the cache.
    foreach ($host in $script:WarmupHosts) {
        try {
            $null = Resolve-DnsName $host -ErrorAction Stop
        } catch { }
    }
}