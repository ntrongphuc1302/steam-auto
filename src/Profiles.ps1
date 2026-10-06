# Profiles.ps1
# The 5 DNS profiles we know how to apply. Order matters: Prober will
# test them in this order, but the final pick is the highest score,
# not the first to pass.

Set-StrictMode -Version Latest

$script:Profiles = [ordered]@{

    'Cloudflare' = [pscustomobject]@{
        Name        = 'Cloudflare'
        DoH         = $false
        IPv4        = @('1.1.1.1', '1.0.0.1')
        IPv6        = @('2606:4700:4700::1111', '2606:4700:4700::1001')
        DohTemplate = $null
        Description = 'Cloudflare plain DNS - fast, no DoH'
    }

    'Google' = [pscustomobject]@{
        Name        = 'Google'
        DoH         = $false
        IPv4        = @('8.8.8.8', '8.8.4.4')
        IPv6        = @('2001:4860:4860::8888', '2001:4860:4860::8844')
        DohTemplate = $null
        Description = 'Google plain DNS - solid fallback'
    }

    'CloudflareDoH' = [pscustomobject]@{
        Name        = 'CloudflareDoH'
        DoH         = $true
        IPv4        = @('1.1.1.1', '1.0.0.1')
        IPv6        = @('2606:4700:4700::1111', '2606:4700:4700::1001')
        DohTemplate = 'https://cloudflare-dns.com/dns-query'
        Description = 'Cloudflare + DoH - beats IP/SNI blocking'
    }

    'GoogleDoH' = [pscustomobject]@{
        Name        = 'GoogleDoH'
        DoH         = $true
        IPv4        = @('8.8.8.8', '8.8.4.4')
        IPv6        = @('2001:4860:4860::8888', '2001:4860:4860::8844')
        DohTemplate = 'https://dns.google/dns-query'
        Description = 'Google + DoH - if Cloudflare DoH fails'
    }

    'Quad9' = [pscustomobject]@{
        Name        = 'Quad9'
        DoH         = $false
        IPv4        = @('9.9.9.9', '149.112.112.112')
        IPv6        = @('2620:fe::fe', '2620:fe::9')
        DohTemplate = $null
        Description = 'Quad9 plain DNS - last resort, security focused'
    }
}

function Get-AllProfiles { $script:Profiles.Values }

function Get-ProfileByName {
    param([Parameter(Mandatory)][string]$Name)
    if ($script:Profiles.Contains($Name)) { return $script:Profiles[$Name] }
    return $null
}