function Get-LongRunningJob {
    <#
    .SYNOPSIS
        Returns SQL Server Agent jobs currently running longer than their historical average.

    .DESCRIPTION
        Compares the current runtime of each executing Agent job against its average successful
        run duration from history. Jobs running longer than (average * Multiplier) are returned.

        Jobs with no successful history are excluded — there is no baseline to compare against.

        IMPORTANT: SQL Server SMO Job objects do not expose an actual start time for a currently
        running job. This function uses LastRunDate as a proxy for the current start time. On jobs
        that run infrequently, LastRunDate may not reflect the current execution's actual start,
        leading to inaccurate current duration estimates. This limitation is inherent to the
        SMO interface.

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER Multiplier
        How many times the average successful duration a job must exceed to be flagged.
        Default is 2.0.

    .PARAMETER ExcludeJob
        One or more job names to exclude. Use this for known long-running maintenance jobs
        that have no meaningful average (e.g., monthly index rebuilds).

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-LongRunningJob -SqlInstance 'SQL01'

        Returns jobs on SQL01 currently running more than 2x their average duration.

    .EXAMPLE
        Get-LongRunningJob -SqlInstance 'SQL01' -Multiplier 3.0 -ExcludeJob 'DBAOps - Index Maintenance'

        Flags jobs running more than 3x their average, skipping the index maintenance job.

    .EXAMPLE
        'SQL01', 'SQL02' | Get-LongRunningJob | Select-Object SqlInstance, JobName, CurrentDuration, AvgDuration, Multiplier

        Returns overdue jobs across two instances.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [double] $Multiplier = 2.0,

        [string[]] $ExcludeJob,

        [switch] $EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-LongRunningJob: Failed to connect to $instance : $_"
                continue
            }

            Write-Verbose "Checking for long-running jobs on $($server.DomainInstanceName)"

            $splatRunning = @{
                SqlInstance = $instance
            }
            if ($SqlCredential) { $splatRunning['SqlCredential'] = $SqlCredential }

            try {
                $running = Get-DbaRunningJob @splatRunning |
                    Where-Object { $_.Name -notin $ExcludeJob }
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-LongRunningJob: Failed to retrieve running jobs from $instance : $_"
                continue
            }

            foreach ($job in $running) {
                $splatHistory = @{
                    SqlInstance     = $instance
                    Job             = $job.Name
                    ExcludeJobSteps = $true
                    EnableException = $true
                }
                if ($SqlCredential) { $splatHistory['SqlCredential'] = $SqlCredential }

                try {
                    $history = Get-DbaAgentJobHistory @splatHistory |
                        Where-Object { $_.Status -eq 'Succeeded' }
                } catch {
                    Write-Verbose "Get-LongRunningJob: Could not retrieve history for '$($job.Name)' on $instance : $_"
                    continue
                }

                if (-not $history) { continue }

                $avgSeconds     = ($history | ForEach-Object { $_.Duration.TotalSeconds } | Measure-Object -Average).Average
                $currentSeconds = [math]::Max(0, (New-TimeSpan -Start $job.LastRunDate -End (Get-Date)).TotalSeconds)

                if ($currentSeconds -gt ($avgSeconds * $Multiplier)) {
                    [PSCustomObject]@{
                        PSTypeName      = 'DbaToolbox.LongRunningJob'
                        ComputerName    = $server.ComputerName
                        InstanceName    = $server.InstanceName
                        SqlInstance     = $server.DomainInstanceName
                        JobName         = $job.Name
                        StartDate       = $job.LastRunDate
                        CurrentDuration = [timespan]::FromSeconds([math]::Round($currentSeconds, 0))
                        AvgDuration     = [timespan]::FromSeconds([math]::Round($avgSeconds, 0))
                        Multiplier      = [math]::Round($currentSeconds / $avgSeconds, 1)
                    }
                }
            }
        }
    }

    end {}
}
