function Get-TopQuery {
    <#
    .SYNOPSIS
        Returns the top queries from the plan cache ranked by CPU, logical reads, or logical writes.

    .DESCRIPTION
        Queries sys.dm_exec_query_stats and sys.dm_exec_sql_text on one or more SQL Server
        instances. Results reflect cumulative stats since the last plan cache flush or service
        restart — a high-ranking query may have run millions of times over weeks rather than
        representing a current problem. Cross-reference with blocking and wait stats to confirm
        whether a query is actively causing issues.

        All three metric sets (CPU, reads, writes) are always populated on each output row.
        Use SortBy to control the ranking; the caller can select whichever metric column they need.

        Plan cache entries can be evicted under memory pressure. If a known problem query is
        not appearing, it may have been flushed.

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER Top
        Number of queries to return per instance. Default is 25.

    .PARAMETER SortBy
        Which metric to rank by. Valid values: CPU, LogicalReads, LogicalWrites.
        Default is CPU.

    .PARAMETER ExcludeInternal
        When specified, filters out queries from XE sessions, monitoring tools, and internal
        SQL Server procedures (sp_WhoIsActive, sp_Blitz*, sysschedules, etc.).

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-TopQuery -SqlInstance 'SQL01'

        Returns the top 25 CPU consumers from the plan cache on SQL01.

    .EXAMPLE
        Get-TopQuery -SqlInstance 'SQL01' -SortBy LogicalReads -Top 50

        Returns the top 50 queries by logical reads.

    .EXAMPLE
        'SQL01', 'SQL02' | Get-TopQuery -ExcludeInternal | Select-Object SqlInstance, DatabaseName, TotalCpuSec, QueryText

        Returns CPU leaders across two instances, suppressing internal monitoring queries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [ValidateRange(1, [int]::MaxValue)]
        [int] $Top = 25,

        [ValidateSet('CPU', 'LogicalReads', 'LogicalWrites')]
        [string] $SortBy = 'CPU',

        [switch] $ExcludeInternal,

        [switch] $EnableException
    )

    begin {
        $sortColumnMap = @{
            CPU           = '[qs].[total_worker_time]'
            LogicalReads  = '[qs].[total_logical_reads]'
            LogicalWrites = '[qs].[total_logical_writes]'
        }
        $sortColumn = $sortColumnMap[$SortBy]

        # $excludeFilter contains only hardcoded literal patterns — no user input is interpolated.
        $excludeFilter = if ($ExcludeInternal) {
            "AND [qt].[text] NOT LIKE '%#XEStaging%'
     AND [qt].[text] NOT LIKE '%dm_xe_session%'
     AND [qt].[text] NOT LIKE '%ring_buffer%'
     AND [qt].[text] NOT LIKE '%target_data%'
     AND [qt].[text] NOT LIKE '%dm_exec_query_stats%'
     AND [qt].[text] NOT LIKE '%sp_WhoIsActive%'
     AND [qt].[text] NOT LIKE '%sp_Blitz%'
     AND [qt].[text] NOT LIKE '%sysschedules%'
     AND [qt].[text] NOT LIKE '%sysjobhistory%'
     AND [qt].[text] NOT LIKE '%tmp_replication_status%'
     AND [qt].[text] NOT LIKE '%#tmp%'"
        } else { '' }

        $query = "
SELECT TOP (@TopN)
    COALESCE(DB_NAME([qt].[dbid]), '<ad hoc>')                               AS DatabaseName,
    [qs].[execution_count]                                                   AS ExecutionCount,
    [qs].[total_worker_time]       / 1000000.0                               AS TotalCpuSec,
    [qs].[total_worker_time]       / [qs].[execution_count] / 1000000.0      AS AvgCpuSec,
    [qs].[total_logical_reads]                                               AS TotalLogicalReads,
    [qs].[total_logical_reads]     / [qs].[execution_count]                  AS AvgLogicalReads,
    [qs].[total_logical_writes]                                              AS TotalLogicalWrites,
    [qs].[total_logical_writes]    / [qs].[execution_count]                  AS AvgLogicalWrites,
    [qs].[total_elapsed_time]      / [qs].[execution_count] / 1000000.0      AS AvgElapsedSec,
    SUBSTRING(
        [qt].[text],
        ([qs].[statement_start_offset] / 2) + 1,
        ((CASE [qs].[statement_end_offset]
            WHEN -1 THEN DATALENGTH([qt].[text])
            ELSE [qs].[statement_end_offset]
          END - [qs].[statement_start_offset]) / 2) + 1
    )                                                                        AS QueryText
FROM [sys].[dm_exec_query_stats]             AS qs
CROSS APPLY [sys].[dm_exec_sql_text]([qs].[sql_handle]) AS qt
WHERE 1 = 1
$excludeFilter
ORDER BY $sortColumn DESC;
"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-TopQuery: Failed to connect to $instance : $_"
                continue
            }

            Write-Verbose "Querying top $Top queries by $SortBy on $($server.DomainInstanceName)"

            $splatQuery = @{
                SqlInstance     = $server
                Database        = 'master'
                Query           = $query
                SqlParameter    = @{ TopN = $Top }
                EnableException = $true
            }

            try {
                $rows = Invoke-DbaQuery @splatQuery
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-TopQuery: Query failed on $instance : $_"
                continue
            }

            foreach ($row in $rows) {
                [PSCustomObject]@{
                    PSTypeName         = 'DbaToolbox.TopQuery'
                    ComputerName       = $server.ComputerName
                    InstanceName       = $server.InstanceName
                    SqlInstance        = $server.DomainInstanceName
                    DatabaseName       = $row.DatabaseName
                    ExecutionCount     = $row.ExecutionCount
                    TotalCpuSec        = $row.TotalCpuSec
                    AvgCpuSec          = $row.AvgCpuSec
                    TotalLogicalReads  = $row.TotalLogicalReads
                    AvgLogicalReads    = $row.AvgLogicalReads
                    TotalLogicalWrites = $row.TotalLogicalWrites
                    AvgLogicalWrites   = $row.AvgLogicalWrites
                    AvgElapsedSec      = $row.AvgElapsedSec
                    QueryText          = $row.QueryText
                }
            }
        }
    }

    end {}
}
