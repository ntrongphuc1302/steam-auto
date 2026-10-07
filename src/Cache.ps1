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

    # First pass: clear cache so we know entries are freshly resolved.
    ipconfig /flushdns | Out-Null
    # Second pass: resolve each host so entries land in the local resolver
    # cache. We use $h instead of $host because $host is an automatic
    # read-only variable in PowerShell.
    foreach ($h in $script:WarmupHosts) {
        try {
            $null = Resolve-DnsName $h -ErrorAction Stop
        } catch {
            # OK if one of them fails; cache warmup is best-effort.
        }
    }
}