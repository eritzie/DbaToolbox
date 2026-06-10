function Get-DeadlockHistory {
    <#
    .SYNOPSIS
        Returns deadlock events recorded in DBAOps.trace.DeadlockHistory.

    .DESCRIPTION
        Queries the DBAOps.trace.DeadlockHistory table which is populated every 5 minutes
        from the system_health ring buffer via the 'DBAOps - Capture Deadlocks' Agent job.
        No custom XE session is required — system_health is always on.

        Default output: recent deadlock events sorted by EventTime DESC.
        -Summary: returns event counts grouped by database.
        -Id N: returns the full deadlock graph XML for a specific DeadlockId.

        Paste DeadlockGraph XML output into SSMS to view the visual deadlock graph.

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER Database
        The database where DBAOps resides. Default is 'DBAOps'.

    .PARAMETER Top
        Number of recent deadlock events to return. Default is 25. Ignored when -Summary
        or -Id is specified.

    .PARAMETER Summary
        Returns deadlock frequency grouped by database instead of individual events.

    .PARAMETER Id
        Returns the full deadlock graph XML for a specific DeadlockId. Mutually exclusive
        with -Summary.

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-DeadlockHistory -SqlInstance 'SQL01'

        Returns the 25 most recent deadlock events on SQL01.

    .EXAMPLE
        Get-DeadlockHistory -SqlInstance 'SQL01' -Summary

        Returns deadlock counts grouped by database.

    .EXAMPLE
        Get-DeadlockHistory -SqlInstance 'SQL01' -Id 42

        Returns the full deadlock graph XML for DeadlockId 42.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [string] $Database = 'DBAOps',

        [Parameter(ParameterSetName = 'Default')]
        [int] $Top = 25,

        [Parameter(ParameterSetName = 'Summary')]
        [switch] $Summary,

        [Parameter(ParameterSetName = 'Graph')]
        [Nullable[int]] $Id,

        [switch] $EnableException
    )

    begin {
        $recentQuery = "
SELECT TOP (@TopN)
    [DeadlockId],
    [EventTime],
    [DatabaseName],
    [VictimProcess],
    [CapturedAt]
FROM [trace].[DeadlockHistory]
ORDER BY [EventTime] DESC;
"
        $summaryQuery = "
SELECT
    [DatabaseName],
    COUNT(*)         AS DeadlockCount,
    MIN([EventTime]) AS FirstSeen,
    MAX([EventTime]) AS LastSeen
FROM [trace].[DeadlockHistory]
GROUP BY [DatabaseName]
ORDER BY DeadlockCount DESC;
"
        $graphQuery = "
SELECT
    [DeadlockId],
    [EventTime],
    [DatabaseName],
    [VictimProcess],
    [DeadlockGraph]
FROM [trace].[DeadlockHistory]
WHERE [DeadlockId] = @DeadlockId;
"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-DeadlockHistory: Failed to connect to $instance : $_"
                continue
            }

            Write-Verbose "Querying deadlock history on $($server.DomainInstanceName)"

            $splatBase = @{
                SqlInstance     = $instance
                Database        = $Database
                EnableException = $true
            }
            if ($SqlCredential) { $splatBase['SqlCredential'] = $SqlCredential }

            if ($Summary) {
                $splatQuery = $splatBase + @{ Query = $summaryQuery }

                try {
                    $rows = Invoke-DbaQuery @splatQuery
                } catch {
                    if ($EnableException) { throw }
                    Write-Warning "Get-DeadlockHistory: Query failed on $instance : $_"
                    continue
                }

                foreach ($row in $rows) {
                    [PSCustomObject]@{
                        PSTypeName    = 'DbaToolbox.DeadlockSummary'
                        ComputerName  = $server.ComputerName
                        InstanceName  = $server.InstanceName
                        SqlInstance   = $server.DomainInstanceName
                        DatabaseName  = $row.DatabaseName
                        DeadlockCount = $row.DeadlockCount
                        FirstSeen     = $row.FirstSeen
                        LastSeen      = $row.LastSeen
                    }
                }

            } elseif ($null -ne $Id) {
                $splatQuery = $splatBase + @{
                    Query        = $graphQuery
                    SqlParameter = @{ DeadlockId = $Id }
                }

                try {
                    $rows = Invoke-DbaQuery @splatQuery
                } catch {
                    if ($EnableException) { throw }
                    Write-Warning "Get-DeadlockHistory: Query failed on $instance : $_"
                    continue
                }

                foreach ($row in $rows) {
                    [PSCustomObject]@{
                        PSTypeName    = 'DbaToolbox.DeadlockGraph'
                        ComputerName  = $server.ComputerName
                        InstanceName  = $server.InstanceName
                        SqlInstance   = $server.DomainInstanceName
                        DeadlockId    = $row.DeadlockId
                        EventTime     = $row.EventTime
                        DatabaseName  = $row.DatabaseName
                        VictimProcess = $row.VictimProcess
                        DeadlockGraph = $row.DeadlockGraph
                    }
                }

            } else {
                $splatQuery = $splatBase + @{
                    Query        = $recentQuery
                    SqlParameter = @{ TopN = $Top }
                }

                try {
                    $rows = Invoke-DbaQuery @splatQuery
                } catch {
                    if ($EnableException) { throw }
                    Write-Warning "Get-DeadlockHistory: Query failed on $instance : $_"
                    continue
                }

                foreach ($row in $rows) {
                    [PSCustomObject]@{
                        PSTypeName    = 'DbaToolbox.DeadlockEvent'
                        ComputerName  = $server.ComputerName
                        InstanceName  = $server.InstanceName
                        SqlInstance   = $server.DomainInstanceName
                        DeadlockId    = $row.DeadlockId
                        EventTime     = $row.EventTime
                        DatabaseName  = $row.DatabaseName
                        VictimProcess = $row.VictimProcess
                        CapturedAt    = $row.CapturedAt
                    }
                }
            }
        }
    }

    end {}
}
