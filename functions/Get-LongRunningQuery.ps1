function Get-LongRunningQuery {
    <#
    .SYNOPSIS
        Returns queries that have been executing longer than a threshold on one or more
        SQL Server instances.

    .DESCRIPTION
        Uses sp_WhoIsActive (via Invoke-DbaWhoIsActive) to capture currently executing
        sessions and filters by elapsed time. The elapsed_time column from sp_WhoIsActive
        is a formatted time string (h:mm:ss.fff) — this function parses it correctly as
        a TimeSpan before comparing against the threshold.

        Sessions where elapsed_time cannot be parsed are silently skipped.

        Requires sp_WhoIsActive installed in master on each instance.
        Install with: Install-DbaWhoIsActive -SqlInstance <instance>

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER ThresholdSeconds
        Minimum elapsed time in seconds to include a session. Default is 5.

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-LongRunningQuery -SqlInstance 'SQL01'

        Returns queries running longer than 5 seconds on SQL01.

    .EXAMPLE
        Get-LongRunningQuery -SqlInstance 'SQL01' -ThresholdSeconds 30

        Returns queries running longer than 30 seconds.

    .EXAMPLE
        'SQL01', 'SQL02' | Get-LongRunningQuery | Sort-Object ElapsedTime -Descending

        Returns long-running queries across two instances, worst first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [int] $ThresholdSeconds = 5,

        [switch] $EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-LongRunningQuery: Failed to connect to $instance : $_"
                continue
            }

            Write-Verbose "Checking for long-running queries on $($server.DomainInstanceName)"

            $splatWia = @{
                SqlInstance      = $instance
                FindBlockLeaders = $true
                GetOuterCommand  = $true
                As               = 'PSObject'
            }
            if ($SqlCredential) { $splatWia['SqlCredential'] = $SqlCredential }

            try {
                $sessions = Invoke-DbaWhoIsActive @splatWia
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-LongRunningQuery: sp_WhoIsActive failed on $instance : $_"
                continue
            }

            foreach ($session in $sessions) {
                # elapsed_time from sp_WhoIsActive is a formatted string (e.g. '0:00:05.123'),
                # not milliseconds — TryParse handles h:mm:ss.fff correctly.
                $elapsed = [timespan]::Zero
                if (-not [timespan]::TryParse($session.elapsed_time, [ref]$elapsed)) { continue }
                if ($elapsed.TotalSeconds -le $ThresholdSeconds) { continue }

                [PSCustomObject]@{
                    PSTypeName        = 'DbaToolbox.LongRunningQuery'
                    ComputerName      = $server.ComputerName
                    InstanceName      = $server.InstanceName
                    SqlInstance       = $server.DomainInstanceName
                    SessionId         = $session.session_id -as [int]
                    ElapsedTime       = $elapsed
                    BlockingSessionId = $session.blocking_session_id -as [int]
                    DatabaseName      = $session.database_name
                    LoginName         = $session.login_name
                    HostName          = $session.host_name
                    SqlText           = $session.sql_text
                    SqlCommand        = $session.sql_command
                }
            }
        }
    }

    end {}
}
