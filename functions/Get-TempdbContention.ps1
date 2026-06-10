function Get-TempdbContention {
    <#
    .SYNOPSIS
        Returns sessions with active PAGELATCH waits on TempDB allocation pages.

    .DESCRIPTION
        Queries sys.dm_os_waiting_tasks joined to sys.dm_exec_sessions for PAGELATCH_*
        waits on resource pages in database 2 (TempDB). Contention on PFS, GAM, and SGAM
        pages indicates that TempDB needs more data files (best practice: one per logical
        CPU core, up to 8).

        PFS pages occur at file offsets 1, 8088, 16176, etc.
        GAM pages occur at offset 2 and every ~64,000 pages thereafter.
        SGAM pages occur at offset 3 and every ~64,000 pages thereafter.

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
                SqlInstance     = $instance
                Database        = 'master'
                Query           = $query
                EnableException = $true
            }
            if ($SqlCredential) { $splatQuery['SqlCredential'] = $SqlCredential }

            try {
                $rows = Invoke-DbaQuery @splatQuery
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-TempdbContention: Query failed on $instance : $_"
                continue
            }

            foreach ($row in $rows) {
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
                    LoginName            = $row.login_name
                    HostName             = $row.host_name
                    ProgramName          = $row.program_name
                }
            }
        }
    }

    end {}
}
