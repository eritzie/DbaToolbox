function Get-LongRunningQuery {
    <#
    .SYNOPSIS
        Returns queries that have been executing longer than a threshold on one or more
        SQL Server instances.

    .DESCRIPTION
        Uses sp_WhoIsActive (via Invoke-DbaWhoIsActive) to capture currently executing
        sessions and filters by elapsed time. Elapsed time is computed from the start_time
        and collection_time datetime columns rather than the formatted runtime string
        ('dd hh:mm:ss.mss'), so multi-day runtimes are handled correctly.

        Sessions without a valid start_time are silently skipped.

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
                SqlInstance     = $server
                GetOuterCommand = $true
                As              = 'PSObject'
            }

            try {
                $sessions = Invoke-DbaWhoIsActive @splatWia
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-LongRunningQuery: sp_WhoIsActive failed on $instance : $_"
                continue
            }

            foreach ($session in $sessions) {
                # sp_WhoIsActive has no elapsed_time column; its runtime column is the
                # formatted string 'dd hh:mm:ss.mss', which TimeSpan cannot parse past 24h.
                # start_time and collection_time are real datetimes — compute from those.
                if ($session.start_time -isnot [datetime] -or $session.collection_time -isnot [datetime]) { continue }
                $elapsed = New-TimeSpan -Start $session.start_time -End $session.collection_time
                if ($elapsed.TotalSeconds -le $ThresholdSeconds) { continue }

                [PSCustomObject]@{
                    PSTypeName        = 'DbaToolbox.LongRunningQuery'
                    ComputerName      = $server.ComputerName
                    InstanceName      = $server.InstanceName
                    SqlInstance       = $server.DomainInstanceName
                    SessionId         = $session.session_id -as [int]
                    ElapsedTime       = $elapsed
                    Status            = $session.status
                    BlockingSessionId = $session.blocking_session_id -as [int]
                    DatabaseName      = $session.database_name
                    LoginName         = $session.login_name
                    HostName          = $session.host_name
                    ProgramName       = $session.program_name
                    SqlText           = $session.sql_text
                    SqlCommand        = $session.sql_command
                }
            }
        }
    }

    end {}
}
