function Get-OpenTransaction {
    <#
    .SYNOPSIS
        Returns sessions with open (uncommitted or un-rolled-back) transactions.

    .DESCRIPTION
        Uses sp_WhoIsActive with -GetTransactionInfo and -ShowSleepingSpids 2 to surface
        sessions that have an open transaction regardless of current session state.

        Sleeping sessions with open transactions are particularly risky — the application
        may have abandoned the transaction while locks remain held indefinitely.

        Requires sp_WhoIsActive installed in master on each instance.
        Install with: Install-DbaWhoIsActive -SqlInstance <instance>

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-OpenTransaction -SqlInstance 'SQL01'

        Returns all sessions with open transactions on SQL01.

    .EXAMPLE
        'SQL01', 'SQL02' | Get-OpenTransaction | Where-Object Status -eq 'sleeping'

        Returns sleeping sessions with open transactions across two instances.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [switch] $EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-OpenTransaction: Failed to connect to $instance : $_"
                continue
            }

            Write-Verbose "Checking for open transactions on $($server.DomainInstanceName)"

            $splatWia = @{
                SqlInstance        = $server
                GetTransactionInfo = $true
                ShowSleepingSpids  = 2
                As                 = 'PSObject'
            }

            try {
                $sessions = Invoke-DbaWhoIsActive @splatWia
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-OpenTransaction: sp_WhoIsActive failed on $instance : $_"
                continue
            }

            foreach ($session in ($sessions | Where-Object {
                ($_.open_tran_count -as [int]) -gt 0
            })) {
                [PSCustomObject]@{
                    PSTypeName        = 'DbaToolbox.OpenTransaction'
                    ComputerName      = $server.ComputerName
                    InstanceName      = $server.InstanceName
                    SqlInstance       = $server.DomainInstanceName
                    SessionId         = $session.session_id -as [int]
                    Status            = $session.status
                    BlockingSessionId = $session.blocking_session_id -as [int]
                    OpenTranCount     = $session.open_tran_count -as [int]
                    TranStartTime     = $session.tran_start_time
                    TranLogWrites     = $session.tran_log_writes
                    ImplicitTran      = $session.implicit_tran
                    DatabaseName      = $session.database_name
                    LoginName         = $session.login_name
                    HostName          = $session.host_name
                    SqlText           = $session.sql_text
                }
            }
        }
    }

    end {}
}
