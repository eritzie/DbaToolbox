function Get-VersionStoreUsage {
    <#
    .SYNOPSIS
        Returns TempDB version store usage totals, per-database breakdown, and databases
        with snapshot isolation enabled.

    .DESCRIPTION
        Emits three output types:

        DbaToolbox.VersionStoreTotal — one row per instance with total version store,
        user object, and internal object page counts from sys.dm_db_file_space_usage.

        DbaToolbox.VersionStoreUsage — one row per database from
        sys.dm_tran_version_store_space_usage. Requires SQL Server 2016 SP2 or later.
        On older instances a warning is written and this type is skipped.

        DbaToolbox.SnapshotIsolationDatabase — databases with RCSI or snapshot isolation
        enabled (from sys.databases). These are the consumers of version store space.

        Excessive version store growth is usually caused by a long-running open transaction
        holding back version cleanup. Cross-reference with Get-OpenTransaction.

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-VersionStoreUsage -SqlInstance 'SQL01'

        Returns version store totals, per-database usage, and snapshot isolation state for SQL01.

    .EXAMPLE
        'SQL01', 'SQL02' | Get-VersionStoreUsage |
            Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.VersionStoreUsage' } |
            Sort-Object ReservedMB -Descending

        Returns only per-database usage rows sorted by size.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [switch] $EnableException
    )

    begin {
        $totalQuery = "
SELECT
    [version_store_reserved_page_count]   * 8 / 1024 AS VersionStoreMB,
    [user_object_reserved_page_count]     * 8 / 1024 AS UserObjectMB,
    [internal_object_reserved_page_count] * 8 / 1024 AS InternalObjectMB
FROM [sys].[dm_db_file_space_usage]
WHERE [database_id] = 2;
"
        # sys.dm_tran_version_store_space_usage requires SQL Server 2016 SP2+
        $perDbQuery = "
SELECT
    DB_NAME([database_id])            AS DatabaseName,
    [reserved_page_count] * 8 / 1024  AS ReservedMB,
    [reserved_space_kb]   / 1024       AS ReservedSpaceMB
FROM [sys].[dm_tran_version_store_space_usage]
ORDER BY [reserved_page_count] DESC;
"
        $snapshotQuery = "
SELECT
    [name]                          AS DatabaseName,
    [snapshot_isolation_state_desc] AS SnapshotState,
    [is_read_committed_snapshot_on] AS RCSIEnabled
FROM [sys].[databases]
WHERE [snapshot_isolation_state] != 0
   OR [is_read_committed_snapshot_on] = 1
ORDER BY [name];
"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-VersionStoreUsage: Failed to connect to $instance : $_"
                continue
            }

            Write-Verbose "Getting version store usage on $($server.DomainInstanceName)"

            $splatBase = @{
                SqlInstance     = $instance
                EnableException = $true
            }
            if ($SqlCredential) { $splatBase['SqlCredential'] = $SqlCredential }

            # --- Version Store Totals ---
            try {
                $totals = Invoke-DbaQuery @splatBase -Database 'tempdb' -Query $totalQuery
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-VersionStoreUsage: Total query failed on $instance : $_"
                continue
            }

            foreach ($row in $totals) {
                [PSCustomObject]@{
                    PSTypeName       = 'DbaToolbox.VersionStoreTotal'
                    ComputerName     = $server.ComputerName
                    InstanceName     = $server.InstanceName
                    SqlInstance      = $server.DomainInstanceName
                    VersionStoreMB   = $row.VersionStoreMB
                    UserObjectMB     = $row.UserObjectMB
                    InternalObjectMB = $row.InternalObjectMB
                }
            }

            # --- Per-Database Version Store (SQL 2016 SP2+) ---
            try {
                $perDb = Invoke-DbaQuery @splatBase -Database 'master' -Query $perDbQuery
                foreach ($row in $perDb) {
                    [PSCustomObject]@{
                        PSTypeName     = 'DbaToolbox.VersionStoreUsage'
                        ComputerName   = $server.ComputerName
                        InstanceName   = $server.InstanceName
                        SqlInstance    = $server.DomainInstanceName
                        DatabaseName   = $row.DatabaseName
                        ReservedMB     = $row.ReservedMB
                        ReservedSpaceMB = $row.ReservedSpaceMB
                    }
                }
            } catch {
                Write-Warning "Get-VersionStoreUsage: Per-database version store query not available on $instance (requires SQL 2016 SP2+)"
            }

            # --- Snapshot Isolation Databases ---
            try {
                $snapDbs = Invoke-DbaQuery @splatBase -Database 'master' -Query $snapshotQuery
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-VersionStoreUsage: Snapshot isolation query failed on $instance : $_"
                continue
            }

            foreach ($row in $snapDbs) {
                [PSCustomObject]@{
                    PSTypeName   = 'DbaToolbox.SnapshotIsolationDatabase'
                    ComputerName = $server.ComputerName
                    InstanceName = $server.InstanceName
                    SqlInstance  = $server.DomainInstanceName
                    DatabaseName = $row.DatabaseName
                    SnapshotState = $row.SnapshotState
                    RCSIEnabled  = $row.RCSIEnabled
                }
            }
        }
    }

    end {}
}
