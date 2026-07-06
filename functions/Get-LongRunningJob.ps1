function Get-LongRunningJob {
    <#
    .SYNOPSIS
        Returns SQL Server Agent jobs currently running longer than their historical average.

    .DESCRIPTION
        Compares the current runtime of each executing Agent job against its average successful
        run duration from history. Jobs running longer than (average * Multiplier) are returned.

        Jobs with no successful history — or whose successful runs all report zero-second
        durations — are excluded; there is no meaningful baseline to compare against.

        The current start time comes from the StartDate property that Get-DbaRunningJob
        attaches from msdb.dbo.sysjobactivity.start_execution_date. If StartDate is not
        populated, LastRunDate is used as a fallback proxy, which may be inaccurate for
        infrequently running jobs.

        The average is computed from successful runs in the last 30 days of job history
        so the baseline reflects recent behavior.

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

            try {
                $running = @(Get-DbaRunningJob -SqlInstance $server |
                    Where-Object { $_.Name -notin $ExcludeJob })
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-LongRunningJob: Failed to retrieve running jobs from $instance : $_"
                continue
            }

            if (-not $running) { continue }

            # One history call for all running jobs, bounded to the last 30 days
            $splatHistory = @{
                SqlInstance     = $server
                Job             = $running.Name
                StartDate       = (Get-Date).AddDays(-30)
                ExcludeJobSteps = $true
                EnableException = $true
            }

            try {
                $history = Get-DbaAgentJobHistory @splatHistory |
                    Where-Object { $_.Status -eq 'Succeeded' } |
                    Group-Object -Property Job -AsHashTable -AsString
            } catch {
                Write-Verbose "Get-LongRunningJob: Could not retrieve job history on $instance : $_"
                continue
            }

            if (-not $history) { continue }

            foreach ($job in $running) {
                $jobHistory = $history[$job.Name]
                if (-not $jobHistory) { continue }

                $avgSeconds = ($jobHistory | ForEach-Object { $_.Duration.TotalSeconds } | Measure-Object -Average).Average
                if ($avgSeconds -le 0) { continue }

                # StartDate comes from sysjobactivity.start_execution_date via Get-DbaRunningJob;
                # LastRunDate is a fallback proxy only
                $startDate      = if ($job.StartDate) { $job.StartDate } else { $job.LastRunDate }
                $currentSeconds = [math]::Max(0, (New-TimeSpan -Start $startDate -End (Get-Date)).TotalSeconds)

                if ($currentSeconds -gt ($avgSeconds * $Multiplier)) {
                    [PSCustomObject]@{
                        PSTypeName      = 'DbaToolbox.LongRunningJob'
                        ComputerName    = $server.ComputerName
                        InstanceName    = $server.InstanceName
                        SqlInstance     = $server.DomainInstanceName
                        JobName         = $job.Name
                        StartDate       = $startDate
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
