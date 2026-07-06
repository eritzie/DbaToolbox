function Get-WaitStatistic {
    <#
    .SYNOPSIS
        Returns SQL Server wait statistics — cumulative since restart, or sampled over
        an interval to show current activity.

    .DESCRIPTION
        Wraps dbatools Get-DbaWaitStatistic, which returns cumulative wait stats since
        the last restart (or Clear-DbaWaitStatistics) with benign waits filtered out and
        each wait categorized.

        With -SampleSeconds, takes two snapshots that many seconds apart and returns the
        difference — what the server is actually waiting on right now, not since restart.
        Sample rows are emitted as DbaToolbox.WaitSample; cumulative rows as
        DbaToolbox.WaitStatistic.

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER Threshold
        Running-percentage cutoff for cumulative mode: waits are returned until their
        cumulative percentage of total wait time reaches this value. Default is 95.
        Ignored in sample mode (all deltas are returned).

    .PARAMETER IncludeIgnorable
        Include waits that dbatools classifies as ignorable (sleep, queue, and broker
        housekeeping waits). Applies to both modes.

    .PARAMETER SampleSeconds
        Interval length for delta sampling. When set, two snapshots are taken this many
        seconds apart and only the difference is returned.

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-WaitStatistic -SqlInstance 'SQL01'

        Returns cumulative wait stats covering 95% of total wait time on SQL01.

    .EXAMPLE
        Get-WaitStatistic -SqlInstance 'SQL01' -SampleSeconds 10

        Samples for 10 seconds and returns only waits that accumulated during the interval.

    .EXAMPLE
        'SQL01', 'SQL02' | Get-WaitStatistic -Threshold 80

        Returns the top waits covering 80% of wait time across two instances.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [ValidateRange(1, 100)]
        [int] $Threshold = 95,

        [switch] $IncludeIgnorable,

        [ValidateRange(1, 3600)]
        [int] $SampleSeconds,

        [switch] $EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-WaitStatistic: Failed to connect to $instance : $_"
                continue
            }

            $splatWait = @{
                SqlInstance     = $server
                EnableException = $true
            }
            if ($IncludeIgnorable) { $splatWait['IncludeIgnorable'] = $true }

            if ($SampleSeconds) {
                Write-Verbose "Sampling wait statistics on $($server.DomainInstanceName) for $SampleSeconds seconds"

                try {
                    $before = Get-DbaWaitStatistic @splatWait -Threshold 100
                    Start-Sleep -Seconds $SampleSeconds
                    $after = Get-DbaWaitStatistic @splatWait -Threshold 100
                } catch {
                    if ($EnableException) { throw }
                    Write-Warning "Get-WaitStatistic: Wait sampling failed on $instance : $_"
                    continue
                }

                $baseline = @{}
                foreach ($wait in $before) { $baseline[$wait.WaitType] = $wait }

                $deltas = foreach ($wait in $after) {
                    $start        = $baseline[$wait.WaitType]
                    $deltaSeconds = $wait.WaitSeconds - $(if ($start) { $start.WaitSeconds } else { 0 })
                    $deltaSignal  = $wait.SignalSeconds - $(if ($start) { $start.SignalSeconds } else { 0 })
                    $deltaCount   = $wait.WaitCount - $(if ($start) { $start.WaitCount } else { 0 })
                    if ($deltaSeconds -le 0 -and $deltaCount -le 0) { continue }

                    [PSCustomObject]@{
                        WaitType         = $wait.WaitType
                        Category         = $wait.Category
                        DeltaWaitSeconds = [math]::Round($deltaSeconds, 3)
                        DeltaSignalSec   = [math]::Round($deltaSignal, 3)
                        DeltaWaitCount   = $deltaCount
                    }
                }

                $totalDelta = ($deltas | Measure-Object -Property DeltaWaitSeconds -Sum).Sum

                foreach ($delta in ($deltas | Sort-Object DeltaWaitSeconds -Descending)) {
                    $pct = if ($totalDelta -gt 0) {
                        [math]::Round($delta.DeltaWaitSeconds * 100.0 / $totalDelta, 1)
                    } else { 0 }

                    [PSCustomObject]@{
                        PSTypeName       = 'DbaToolbox.WaitSample'
                        ComputerName     = $server.ComputerName
                        InstanceName     = $server.InstanceName
                        SqlInstance      = $server.DomainInstanceName
                        SampleSeconds    = $SampleSeconds
                        WaitType         = $delta.WaitType
                        Category         = $delta.Category
                        WaitSecondsDelta = $delta.DeltaWaitSeconds
                        SignalSecDelta   = $delta.DeltaSignalSec
                        WaitCountDelta   = $delta.DeltaWaitCount
                        Percentage       = $pct
                    }
                }
            } else {
                Write-Verbose "Getting cumulative wait statistics on $($server.DomainInstanceName)"

                try {
                    $waits = Get-DbaWaitStatistic @splatWait -Threshold $Threshold
                } catch {
                    if ($EnableException) { throw }
                    Write-Warning "Get-WaitStatistic: Get-DbaWaitStatistic failed on $instance : $_"
                    continue
                }

                foreach ($wait in $waits) {
                    [PSCustomObject]@{
                        PSTypeName         = 'DbaToolbox.WaitStatistic'
                        ComputerName       = $server.ComputerName
                        InstanceName       = $server.InstanceName
                        SqlInstance        = $server.DomainInstanceName
                        WaitType           = $wait.WaitType
                        Category           = $wait.Category
                        WaitSeconds        = $wait.WaitSeconds
                        ResourceSeconds    = $wait.ResourceSeconds
                        SignalSeconds      = $wait.SignalSeconds
                        WaitCount          = $wait.WaitCount
                        Percentage         = $wait.Percentage
                        AverageWaitSeconds = $wait.AverageWaitSeconds
                        URL                = $wait.URL
                    }
                }
            }
        }
    }

    end {}
}
