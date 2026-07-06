function Get-DatabaseSize {
    <#
    .SYNOPSIS
        Returns database size summary and optionally per-file detail for one or more
        SQL Server instances.

    .DESCRIPTION
        Uses Get-DbaDbFile to retrieve file information and groups results by database
        to produce summary totals (TotalSizeMB, UsedMB, FreeMB, UsedPct).

        With -IncludeFiles, also emits one DbaToolbox.DatabaseFile row per physical file.
        AutoGrowth is flagged with a trailing '*' when percentage-based growth is configured
        (best practice is fixed-size growth in MB). Files with autogrowth turned off
        (growth = 0) show 'Disabled'.

        Size properties from Get-DbaDbFile are [dbasize] objects and must be cast with
        [long] before arithmetic — calling .Bytes is not supported.

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER Database
        Limit results to one or more specific database names.

    .PARAMETER IncludeFiles
        When specified, also emits DbaToolbox.DatabaseFile rows (one per physical file)
        in addition to the summary rows.

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-DatabaseSize -SqlInstance 'SQL01'

        Returns database size summary for all databases on SQL01.

    .EXAMPLE
        Get-DatabaseSize -SqlInstance 'SQL01' -IncludeFiles

        Returns database summary plus individual file detail.

    .EXAMPLE
        Get-DatabaseSize -SqlInstance 'SQL01' -Database 'AppDB', 'ReportDB'

        Returns summary for two specific databases.

    .EXAMPLE
        'SQL01', 'SQL02' | Get-DatabaseSize | Sort-Object TotalSizeMB -Descending

        Returns database sizes across two instances, largest first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [string[]] $Database,

        [switch] $IncludeFiles,

        [switch] $EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-DatabaseSize: Failed to connect to $instance : $_"
                continue
            }

            Write-Verbose "Getting database file info on $($server.DomainInstanceName)"

            $splatFiles = @{
                SqlInstance = $server
            }
            if ($Database) { $splatFiles['Database'] = $Database }

            try {
                $allFiles = Get-DbaDbFile @splatFiles
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-DatabaseSize: Get-DbaDbFile failed on $instance : $_"
                continue
            }

            # --- Database Summary ---
            $allFiles | Group-Object -Property Database | ForEach-Object {
                $files     = $_.Group
                $totalSize = ($files | ForEach-Object { [long]$_.Size }           | Measure-Object -Sum).Sum
                $usedSpace = ($files | ForEach-Object { [long]$_.UsedSpace }      | Measure-Object -Sum).Sum
                $freeSpace = $totalSize - $usedSpace
                $usedPct   = if ($totalSize -gt 0) { [math]::Round($usedSpace * 100.0 / $totalSize, 1) } else { 0 }

                [PSCustomObject]@{
                    PSTypeName   = 'DbaToolbox.DatabaseSize'
                    ComputerName = $server.ComputerName
                    InstanceName = $server.InstanceName
                    SqlInstance  = $server.DomainInstanceName
                    DatabaseName = $_.Name
                    TotalSizeMB  = [math]::Round($totalSize / 1MB, 0)
                    UsedMB       = [math]::Round($usedSpace / 1MB, 0)
                    FreeMB       = [math]::Round($freeSpace / 1MB, 0)
                    UsedPct      = $usedPct
                }
            }

            # --- Per-File Detail ---
            if ($IncludeFiles) {
                foreach ($file in $allFiles) {
                    $sizeMB = [math]::Round([long]$file.Size           / 1MB, 0)
                    $usedMB = [math]::Round([long]$file.UsedSpace      / 1MB, 0)
                    $freeMB = [math]::Round([long]$file.AvailableSpace / 1MB, 0)
                    $s      = [long]$file.Size
                    $pct    = if ($s -gt 0) { [math]::Round([long]$file.UsedSpace * 100.0 / $s, 1) } else { 0 }
                    $growth = if ($file.GrowthType -eq 'Percent') {
                        "$($file.Growth)% *"
                    } elseif (([long]$file.Growth) -eq 0) {
                        'Disabled'
                    } else {
                        "$([math]::Round([long]$file.NextGrowthEventSize / 1MB, 0)) MB"
                    }

                    [PSCustomObject]@{
                        PSTypeName       = 'DbaToolbox.DatabaseFile'
                        ComputerName     = $server.ComputerName
                        InstanceName     = $server.InstanceName
                        SqlInstance      = $server.DomainInstanceName
                        DatabaseName     = $file.Database
                        LogicalName      = $file.LogicalName
                        TypeDescription  = $file.TypeDescription
                        SizeMB           = $sizeMB
                        UsedMB           = $usedMB
                        FreeMB           = $freeMB
                        UsedPct          = $pct
                        AutoGrowth       = $growth
                        PhysicalName     = $file.PhysicalName
                    }
                }
            }
        }
    }

    end {}
}
