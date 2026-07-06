function Get-FailedLogin {
    <#
    .SYNOPSIS
        Returns failed login attempts from the SQL Server error log, grouped by login,
        reason, and client address.

    .DESCRIPTION
        Reads 'Login failed' events (error 18456) from the error log and parses the login
        name, failure reason, and client IP address out of each message. Events are
        grouped by Login + Reason + ClientAddress with a count and first/last seen
        timestamps.

        Uses xp_readerrorlog via Invoke-DbaQuery instead of Get-DbaErrorLog deliberately:
        the search string and time filters are applied server-side, so only matching rows
        cross the wire. Get-DbaErrorLog (SMO) streams the entire log file to the client
        before filtering — observed taking nearly an hour against a 2 GB archive log.

        Only the current error log is read by default. Use -LogNumber to include archived
        logs when the window of interest spans a log cycle.

        The Reason column carries the human-readable failure reason from the error log
        (e.g. 'Password did not match that for the login provided.'), so no state-code
        decoding is required. Note that failed logins only appear in the error log when
        the audit level includes failed logins (the SQL Server default).

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER HoursBack
        How many hours back to search the error log. Default is 24.

    .PARAMETER LogNumber
        Which error log file(s) to read. Default is 0 (the current log). Pass additional
        archive numbers when the search window spans a log cycle, e.g. -LogNumber 0, 1.

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-FailedLogin -SqlInstance 'SQL01'

        Returns failed logins from the last 24 hours on SQL01.

    .EXAMPLE
        Get-FailedLogin -SqlInstance 'SQL01' -HoursBack 168

        Returns failed logins from the last week.

    .EXAMPLE
        'SQL01', 'SQL02' | Get-FailedLogin | Sort-Object FailureCount -Descending

        Returns failed logins across two instances, most frequent first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [ValidateRange(1, [int]::MaxValue)]
        [int] $HoursBack = 24,

        [ValidateRange(0, 99)]
        [int[]] $LogNumber = @(0),

        [switch] $EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-FailedLogin: Failed to connect to $instance : $_"
                continue
            }

            Write-Verbose "Searching error log for failed logins on $($server.DomainInstanceName)"

            # xp_readerrorlog filters server-side: log number, log type (1 = SQL Server),
            # search string, second search string, start time, end time
            $events = foreach ($log in $LogNumber) {
                $splatLog = @{
                    SqlInstance     = $server
                    Database        = 'master'
                    Query           = 'EXEC [master].[dbo].[xp_readerrorlog] @LogNumber, 1, @Search1, NULL, @After, NULL;'
                    SqlParameter    = @{
                        LogNumber = $log
                        Search1   = 'Login failed'
                        After     = (Get-Date).AddHours(-$HoursBack)
                    }
                    EnableException = $true
                }

                try {
                    Invoke-DbaQuery @splatLog
                } catch {
                    if ($EnableException) { throw }
                    Write-Warning "Get-FailedLogin: Error log $log read failed on $instance : $_"
                }
            }

            # Typical message:
            # Login failed for user 'DOMAIN\user'. Reason: Password did not match that
            # for the login provided. [CLIENT: 10.0.0.5]
            $parsed = foreach ($logEvent in $events) {
                $login  = if ($logEvent.Text -match "user '([^']*)'")         { $Matches[1] } else { '<unknown>' }
                $reason = if ($logEvent.Text -match 'Reason:\s*([^\[]+)')     { $Matches[1].Trim() } else { $null }
                $client = if ($logEvent.Text -match '\[CLIENT:\s*([^\]]+)\]') { $Matches[1].Trim() } else { $null }

                [PSCustomObject]@{
                    LogDate       = $logEvent.LogDate
                    Login         = $login
                    Reason        = $reason
                    ClientAddress = $client
                }
            }

            $parsed |
                Group-Object -Property Login, Reason, ClientAddress |
                ForEach-Object {
                    $dates = $_.Group.LogDate | Sort-Object
                    [PSCustomObject]@{
                        PSTypeName    = 'DbaToolbox.FailedLogin'
                        ComputerName  = $server.ComputerName
                        InstanceName  = $server.InstanceName
                        SqlInstance   = $server.DomainInstanceName
                        Login         = $_.Group[0].Login
                        Reason        = $_.Group[0].Reason
                        ClientAddress = $_.Group[0].ClientAddress
                        FailureCount  = $_.Count
                        FirstSeen     = $dates | Select-Object -First 1
                        LastSeen      = $dates | Select-Object -Last 1
                    }
                }
        }
    }

    end {}
}
