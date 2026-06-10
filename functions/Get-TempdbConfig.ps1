function Get-TempdbConfig {
    <#
    .SYNOPSIS
        Returns TempDB best-practice check results and individual file configuration.

    .DESCRIPTION
        Emits two output types from a single call:

        DbaToolbox.TempdbBestPractice — from Test-DbaTempDbConfig. Checks file count,
        file size equality, trace flags, and autogrowth settings against known best practices.

        DbaToolbox.TempdbFile — from tempdb.sys.database_files. Shows size, free space,
        and autogrowth settings per file. Autogrowth is flagged with a trailing '*' when
        percentage-based growth is configured (best practice is fixed-size growth in MB).

        Callers can filter by PSTypeName to process each type separately:
            Get-TempdbConfig -SqlInstance 'SQL01' | Where-Object PSObject.TypeNames[0] -eq 'DbaToolbox.TempdbFile'

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-TempdbConfig -SqlInstance 'SQL01'

        Returns best-practice results and file detail for TempDB on SQL01.

    .EXAMPLE
        Get-TempdbConfig -SqlInstance 'SQL01' | Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.TempdbFile' }

        Returns only file detail rows.

    .EXAMPLE
        'SQL01', 'SQL02' | Get-TempdbConfig | Where-Object { $_ -is [DbaToolbox.TempdbBestPractice] }

        Returns only best-practice rows across two instances.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [switch] $EnableException
    )

    begin {
        $fileQuery = "
SELECT
    [f].[name]                                                            AS FileName,
    [f].[type_desc]                                                       AS FileType,
    [f].[size] * 8 / 1024                                                 AS SizeMB,
    ([f].[size] - FILEPROPERTY([f].[name], 'SpaceUsed')) * 8 / 1024      AS FreeMB,
    CAST(
        (([f].[size] - FILEPROPERTY([f].[name], 'SpaceUsed')) * 100.0)
        / [f].[size] AS decimal(5,1))                                     AS FreePct,
    CASE [f].[is_percent_growth]
        WHEN 1 THEN CAST([f].[growth] AS varchar(20)) + '% *'
        ELSE        CAST([f].[growth] * 8 / 1024 AS varchar(20)) + ' MB'
    END                                                                   AS AutoGrowth,
    [f].[physical_name]                                                   AS PhysicalPath
FROM [sys].[database_files] AS f
ORDER BY [f].[type_desc], [f].[file_id];
"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-TempdbConfig: Failed to connect to $instance : $_"
                continue
            }

            Write-Verbose "Checking TempDB configuration on $($server.DomainInstanceName)"

            # --- Best Practice Check ---
            $splatBp = @{
                SqlInstance = $instance
            }
            if ($SqlCredential) { $splatBp['SqlCredential'] = $SqlCredential }

            try {
                $bpResults = Test-DbaTempDbConfig @splatBp
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-TempdbConfig: Test-DbaTempDbConfig failed on $instance : $_"
            }

            foreach ($bp in $bpResults) {
                [PSCustomObject]@{
                    PSTypeName     = 'DbaToolbox.TempdbBestPractice'
                    ComputerName   = $server.ComputerName
                    InstanceName   = $server.InstanceName
                    SqlInstance    = $server.DomainInstanceName
                    Rule           = $bp.Rule
                    CurrentSetting = $bp.CurrentSetting
                    Recommended    = $bp.Recommended
                    IsBestPractice = $bp.IsBestPractice
                    Notes          = $bp.Notes
                }
            }

            # --- File Detail ---
            $splatFile = @{
                SqlInstance     = $instance
                Database        = 'tempdb'
                Query           = $fileQuery
                EnableException = $true
            }
            if ($SqlCredential) { $splatFile['SqlCredential'] = $SqlCredential }

            try {
                $fileRows = Invoke-DbaQuery @splatFile
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-TempdbConfig: File detail query failed on $instance : $_"
                continue
            }

            foreach ($row in $fileRows) {
                [PSCustomObject]@{
                    PSTypeName   = 'DbaToolbox.TempdbFile'
                    ComputerName = $server.ComputerName
                    InstanceName = $server.InstanceName
                    SqlInstance  = $server.DomainInstanceName
                    FileName     = $row.FileName
                    FileType     = $row.FileType
                    SizeMB       = $row.SizeMB
                    FreeMB       = $row.FreeMB
                    FreePct      = $row.FreePct
                    AutoGrowth   = $row.AutoGrowth
                    PhysicalPath = $row.PhysicalPath
                }
            }
        }
    }

    end {}
}
