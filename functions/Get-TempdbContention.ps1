function Get-TempdbContention {
    <#
    .SYNOPSIS
        Returns sessions with active PAGELATCH waits on TempDB allocation pages.

    .DESCRIPTION
        Queries sys.dm_os_waiting_tasks joined to sys.dm_exec_sessions for PAGELATCH_*
        waits on resource pages in database 2 (TempDB). All TempDB page-latch waits are
        returned; the PageType column classifies each waited-on page as PFS, GAM, SGAM,
        or Other. Contention on PFS, GAM, and SGAM allocation pages indicates that TempDB
        needs more data files (best practice: one per logical CPU core, up to 8).

        Page intervals per the Microsoft pages-and-extents architecture guide:
        PFS  = page 1, then every 8,088 pages.
        GAM  = page 2, repeating per ~64,000-extent (511,232-page) interval.
        SGAM = page 3, on the same interval as GAM.

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-TempdbContention -SqlInstance 'SQL01'

        Returns any sessions currently waiting on TempDB allocation page latches.

    .EXAMPLE
        'SQL01', 'SQL02' | Get-TempdbContention | Sort-Object WaitDurationMs -Descending

        Returns TempDB contention across two instances, worst wait first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [switch] $EnableException
    )

    begin {
        $query = "
SELECT
    [t].[session_id],
    [t].[exec_context_id],
    [t].[wait_type],
    [t].[wait_duration_ms],
    [t].[resource_description],
    [s].[login_name],
    [s].[host_name],
    [s].[program_name]
FROM [sys].[dm_os_waiting_tasks]  AS t
JOIN [sys].[dm_exec_sessions]     AS s
    ON [t].[session_id] = [s].[session_id]
WHERE [t].[wait_type] LIKE 'PAGELATCH_%'
  AND [t].[resource_description] LIKE '2:%'
ORDER BY [t].[wait_duration_ms] DESC;
"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-TempdbContention: Failed to connect to $instance : $_"
                continue
            }

            Write-Verbose "Checking TempDB PAGELATCH waits on $($server.DomainInstanceName)"

            $splatQuery = @{
                SqlInstance     = $server
                Database        = 'master'
                Query           = $query
                EnableException = $true
            }

            try {
                $rows = Invoke-DbaQuery @splatQuery
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-TempdbContention: Query failed on $instance : $_"
                continue
            }

            foreach ($row in $rows) {
                # resource_description is db:file:page — classify allocation pages.
                # Intervals: PFS every 8088 pages from page 1; GAM page 2 and SGAM page 3
                # repeating per 511,232-page (~64,000 extent) interval.
                $pageType = 'Other'
                if ($row.resource_description -match '^\d+:\d+:(\d+)$') {
                    $pageId = [long]$Matches[1]
                    $pageType = if ($pageId -eq 1 -or $pageId % 8088 -eq 0) { 'PFS' }
                    elseif ($pageId -eq 2 -or $pageId % 511232 -eq 0) { 'GAM' }
                    elseif ($pageId -eq 3 -or ($pageId - 1) % 511232 -eq 0) { 'SGAM' }
                    else { 'Other' }
                }

                [PSCustomObject]@{
                    PSTypeName           = 'DbaToolbox.TempdbContention'
                    ComputerName         = $server.ComputerName
                    InstanceName         = $server.InstanceName
                    SqlInstance          = $server.DomainInstanceName
                    SessionId            = $row.session_id
                    ExecContextId        = $row.exec_context_id
                    WaitType             = $row.wait_type
                    WaitDurationMs       = $row.wait_duration_ms
                    ResourceDescription  = $row.resource_description
                    PageType             = $pageType
                    LoginName            = $row.login_name
                    HostName             = $row.host_name
                    ProgramName          = $row.program_name
                }
            }
        }
    }

    end {}
}
