@{
    # Order in which profiles are tried (best score still picks, this is
    # only the probing order).
    ProfilesOrder = @('CloudflareDoH', 'GoogleDoH', 'Cloudflare', 'Google', 'Quad9')

    # Watchdog polling intervals (seconds).
    InitialProbeSeconds   = 60      # when failing
    SteadyProbeSeconds    = 300     # first OK
    StableProbeSeconds    = 900     # second OK
    RockSolidProbeSeconds = 1800    # third OK
    SleepProbeSeconds     = 3600    # fourth+ OK

    # Watchdog exits cleanly every N hours to drop any leaked memory.
    SelfRestartHours      = 6

    # Seconds to wait after applying a profile before verifying.
    VerifyAfterApplySec   = 30

    # Size of the CDN file used for the speed test, in bytes.
    SpeedTestBytes        = 262144

    # Set to true to log every probe. Default false = log only changes.
    LogVerbose             = $false

    # Scoring weights, must sum to 100.
    ScoreWeights = @{
        Latency = 30
        Tcp     = 25
        Https   = 15
        Speed   = 20
        Clean   = 10
    }
}