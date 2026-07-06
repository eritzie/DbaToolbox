function Get-FailedJob {
    <#
    .SYNOPSIS
        Returns every SQL Server Agent job failure within a specified time window.

    .DESCRIPTION
        Queries Agent job history on one or more SQL Server instances and returns every
        job-level failure in the look-back window — including jobs that later succeeded
        on retry. Job steps are excluded from results — only the job-level outcome is
        returned.

        Use HoursBack to control the look-back window (default 24 hours).
        Use ExcludeJob to suppress known expected failures.

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER HoursBack
        How many hours back to look in job history. Default is 24.

    .PARAMETER ExcludeJob
        One or more job names to exclude from results.

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-FailedJob -SqlInstance 'SQL01'

        Returns all jobs that failed in the last 24 hours on SQL01.

    .EXAMPLE
        Get-FailedJob -SqlInstance 'SQL01' -HoursBack 48 -ExcludeJob 'DBAOps - Capture Deadlocks'

        Looks back 48 hours and suppresses a specific job from results.

    .EXAMPLE
        'SQL01', 'SQL02' | Get-FailedJob | Select-Object SqlInstance, JobName, RunDate, Message

        Returns failed jobs across two instances.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [int] $HoursBack = 24,

        [string[]] $ExcludeJob,

        [switch] $EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-FailedJob: Failed to connect to $instance : $_"
                continue
            }

            Write-Verbose "Getting failed job history on $($server.DomainInstanceName)"

            $splatHistory = @{
                SqlInstance     = $server
                StartDate       = (Get-Date).AddHours(-$HoursBack)
                ExcludeJobSteps = $true
                EnableException = $true
            }

            try {
                $history = Get-DbaAgentJobHistory @splatHistory
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-FailedJob: Failed to retrieve job history from $instance : $_"
                continue
            }

            foreach ($row in ($history | Where-Object { $_.Status -eq 'Failed' -and $_.Job -notin $ExcludeJob })) {
                [PSCustomObject]@{
                    PSTypeName   = 'DbaToolbox.FailedJob'
                    ComputerName = $server.ComputerName
                    InstanceName = $server.InstanceName
                    SqlInstance  = $server.DomainInstanceName
                    JobName      = $row.Job
                    RunDate      = $row.RunDate
                    Duration     = $row.Duration
                    Message      = $row.Message
                }
            }
        }
    }

    end {}
}
