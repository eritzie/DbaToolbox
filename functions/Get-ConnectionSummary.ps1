function Get-ConnectionSummary {
    <#
    .SYNOPSIS
        Returns active SQL Server sessions grouped by database, login, host, program, and state.

    .DESCRIPTION
        Retrieves all non-system processes from one or more SQL Server instances via Get-DbaProcess,
        then groups them by Database, Login, Host, Program, Status, and Command.
        ConnectionCount reflects how many sessions share that profile.

        Use Database, Login, and HostName to narrow results to a specific context.
        Idle sessions show null for the Command column — that is normal.

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER Database
        Filter results to a specific database name. Exact match.

    .PARAMETER Login
        Filter results to a specific login name. Exact match.

    .PARAMETER HostName
        Filter results to sessions originating from a specific host. Exact match.

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-ConnectionSummary -SqlInstance 'SQL01'

        Returns all active user sessions on SQL01 grouped by profile.

    .EXAMPLE
        Get-ConnectionSummary -SqlInstance 'SQL01' -Database 'AppDB'

        Returns active sessions scoped to the AppDB database.

    .EXAMPLE
        'SQL01', 'SQL02' | Get-ConnectionSummary -Login 'domain\svc_account'

        Returns sessions for a specific login across two instances.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [string] $Database,

        [string] $Login,

        [string] $HostName,

        [switch] $EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-ConnectionSummary: Failed to connect to $instance : $_"
                continue
            }

            Write-Verbose "Getting active processes on $($server.DomainInstanceName)"

            try {
                $results = Get-DbaProcess -SqlInstance $server -ExcludeSystemSpids
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-ConnectionSummary: Failed to retrieve processes from $instance : $_"
                continue
            }

            if ($Database) { $results = $results | Where-Object Database -eq $Database }
            if ($Login)    { $results = $results | Where-Object Login    -eq $Login    }
            if ($HostName) { $results = $results | Where-Object Host     -eq $HostName }

            $results |
                Group-Object -Property Database, Login, Host, Program, Status, Command |
                ForEach-Object {
                    [PSCustomObject]@{
                        PSTypeName      = 'DbaToolbox.ConnectionSummary'
                        ComputerName    = $server.ComputerName
                        InstanceName    = $server.InstanceName
                        SqlInstance     = $server.DomainInstanceName
                        DatabaseName    = $_.Group[0].Database
                        LoginName       = $_.Group[0].Login
                        Host            = $_.Group[0].Host
                        Program         = $_.Group[0].Program
                        Status          = $_.Group[0].Status
                        Command         = $_.Group[0].Command
                        ConnectionCount = $_.Count
                    }
                }
        }
    }

    end {}
}
