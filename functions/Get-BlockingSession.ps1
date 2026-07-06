function Get-BlockingSession {
    <#
    .SYNOPSIS
        Returns sessions involved in blocking chains on one or more SQL Server instances.

    .DESCRIPTION
        Uses sp_WhoIsActive (via Invoke-DbaWhoIsActive) with -FindBlockLeaders to identify
        sessions that are blocked or acting as head blockers. Only sessions with a non-zero
        blocking_session_id or a positive blocked_session_count are returned.

        With -Detailed, adds lock XML, parallel worker thread information, and the outer
        command via -GetLocks, -GetTaskInfo 2, and -GetOuterCommand. GetTaskInfo 2 includes
        parallel worker threads, which can add noise when parallel queries are running —
        omit it for cleaner output in those cases.

        WaitInfo is the raw sp_WhoIsActive wait_info string, e.g. '(32440753ms)LCK_M_S' —
        duration and wait type combined; aggregated forms appear when multiple tasks wait.

        Requires sp_WhoIsActive installed in master on each instance.
        Install with: Install-DbaWhoIsActive -SqlInstance <instance>

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER Detailed
        Adds lock XML (Locks) and outer command (SqlCommand) to output. Uses -GetLocks,
        -GetTaskInfo 2, and -GetOuterCommand in the sp_WhoIsActive call.

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-BlockingSession -SqlInstance 'SQL01'

        Returns any sessions currently blocked or acting as head blockers on SQL01.

    .EXAMPLE
        Get-BlockingSession -SqlInstance 'SQL01' -Detailed

        Returns blocking sessions with lock XML for deeper analysis.

    .EXAMPLE
        'SQL01', 'SQL02' | Get-BlockingSession | Where-Object BlockedSessionCount -gt 0

        Returns head blockers across two instances.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [switch] $Detailed,

        [switch] $EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-BlockingSession: Failed to connect to $instance : $_"
                continue
            }

            Write-Verbose "Checking for blocking sessions on $($server.DomainInstanceName)"

            $splatWia = @{
                SqlInstance      = $server
                FindBlockLeaders = $true
                As               = 'PSObject'
            }
            if ($Detailed) { $splatWia['GetLocks'] = $true; $splatWia['GetTaskInfo'] = 2; $splatWia['GetOuterCommand'] = $true }

            try {
                $sessions = Invoke-DbaWhoIsActive @splatWia
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-BlockingSession: sp_WhoIsActive failed on $instance : $_"
                continue
            }

            foreach ($session in ($sessions | Where-Object {
                ($_.blocking_session_id -as [int]) -gt 0 -or
                ($_.blocked_session_count -as [int]) -gt 0
            })) {
                [PSCustomObject]@{
                    PSTypeName          = 'DbaToolbox.BlockingSession'
                    ComputerName        = $server.ComputerName
                    InstanceName        = $server.InstanceName
                    SqlInstance         = $server.DomainInstanceName
                    SessionId           = $session.session_id -as [int]
                    BlockingSessionId   = $session.blocking_session_id -as [int]
                    BlockedSessionCount = $session.blocked_session_count -as [int]
                    WaitInfo            = $session.wait_info
                    StartTime           = $session.start_time
                    DatabaseName        = $session.database_name
                    LoginName           = $session.login_name
                    SqlText             = $session.sql_text
                    HostName            = $session.host_name
                    Locks               = $session.locks
                    SqlCommand          = $session.sql_command
                }
            }
        }
    }

    end {}
}
