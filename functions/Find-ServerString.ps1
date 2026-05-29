function Find-ServerString {
    <#
    .SYNOPSIS
        Searches SQL Server instances for a string across SQL modules, Agent job steps,
        and linked server definitions.

    .DESCRIPTION
        Scans one or more SQL Server instances for a given search string across:
          - SQL module definitions (stored procedures, views, functions, triggers)
          - SQL Server Agent job step commands
          - Linked server names and data sources

        Uses parameterized queries via Invoke-DbaQuery. Follows dbatools conventions for
        connection handling, error handling, and pipeline-friendly output.

    .PARAMETER SqlInstance
        One or more SQL Server instances to search. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER SearchString
        The string to search for. Case sensitivity follows the target database/server collation.

    .PARAMETER Database
        Limit the SQL module search to specific database(s). Wildcards accepted.
        Has no effect on AgentJobs or LinkedServers scope.

    .PARAMETER ExcludeDatabase
        Exclude specific database(s) from the SQL module search.

    .PARAMETER Type
        Which targets to search. Defaults to all three.
        Valid values: SqlModules, AgentJobs, LinkedServers.

    .PARAMETER IncludeSystemDatabases
        Include master, model, msdb, and tempdb in the SQL module search.
        Excluded by default.

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Find-ServerString -SqlInstance 'SQL01\INST' -SearchString 'oldserver'

        Searches all three target types on SQL01\INST and returns matching objects.

    .EXAMPLE
        'SQL01', 'SQL02' | Find-ServerString -SearchString 'legacypath' -Type AgentJobs

        Searches only Agent job step commands on two instances via the pipeline.

    .EXAMPLE
        Find-ServerString -SqlInstance 'SQL01' -SearchString 'v-file' -Verbose |
            Out-GridView -Title 'Results'

        Search with verbose progress output, then display results in a grid.

    .EXAMPLE
        Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' -Type SqlModules `
            -Database 'AppDB', 'ReportDB'

        Restricts the SQL module search to two specific databases.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [Parameter(Mandatory)]
        [string] $SearchString,

        [string[]] $Database,

        [string[]] $ExcludeDatabase,

        [ValidateSet('SqlModules', 'AgentJobs', 'LinkedServers')]
        [string[]] $Type = @('SqlModules', 'AgentJobs', 'LinkedServers'),

        [switch] $IncludeSystemDatabases,

        [switch] $EnableException
    )

    begin {
        $sqlModulesQuery = @"
SELECT
    SchemaName = SCHEMA_NAME(o.schema_id),
    ObjectName = o.name,
    ObjectType = o.type_desc,
    Definition = m.definition
FROM sys.sql_modules m
JOIN sys.objects     o ON m.object_id = o.object_id
WHERE CHARINDEX(@Pattern, m.definition) > 0
ORDER BY SchemaName, ObjectName
"@

        $agentJobsQuery = @"
SELECT
    JobName  = j.name,
    StepID   = s.step_id,
    StepName = s.step_name,
    DBName   = s.database_name,
    Command  = s.command
FROM msdb.dbo.sysjobsteps s
JOIN msdb.dbo.sysjobs     j ON s.job_id = j.job_id
WHERE CHARINDEX(@Pattern, s.command) > 0
ORDER BY j.name, s.step_id
"@

        $linkedServersQuery = @"
SELECT
    LinkedServerName = s.name,
    Product          = s.product,
    Provider         = s.provider,
    DataSource       = s.data_source,
    Location         = ISNULL(s.location, '')
FROM sys.servers s
WHERE s.is_linked = 1
  AND (   CHARINDEX(@Pattern, s.name)                  > 0
       OR CHARINDEX(@Pattern, s.data_source)            > 0
       OR CHARINDEX(@Pattern, ISNULL(s.location, ''))   > 0
  )
"@

        $sqlParam = @{ Pattern = $SearchString }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Find-ServerString: Failed to connect to $instance : $_"
                continue
            }

            # --- SQL Modules ---
            if ('SqlModules' -in $Type) {
                $splatGetDb = @{
                    SqlInstance   = $instance
                    ExcludeSystem = (-not $IncludeSystemDatabases.IsPresent)
                }
                if ($SqlCredential)   { $splatGetDb['SqlCredential']   = $SqlCredential }
                if ($Database)        { $splatGetDb['Database']        = $Database }
                if ($ExcludeDatabase) { $splatGetDb['ExcludeDatabase'] = $ExcludeDatabase }

                foreach ($db in (Get-DbaDatabase @splatGetDb)) {
                    Write-Verbose "Searching SQL modules in [$($db.Name)] on $($server.DomainInstanceName)"

                    $splatModuleQuery = @{
                        SqlInstance     = $instance
                        Database        = $db.Name
                        Query           = $sqlModulesQuery
                        SqlParameter    = $sqlParam
                        EnableException = $true
                    }
                    if ($SqlCredential) { $splatModuleQuery['SqlCredential'] = $SqlCredential }

                    try {
                        $rows = Invoke-DbaQuery @splatModuleQuery
                    } catch {
                        if ($EnableException) { throw }
                        Write-Warning "Find-ServerString: SQL module search failed in $($db.Name) on $instance : $_"
                        continue
                    }

                    foreach ($row in $rows) {
                        [PSCustomObject]@{
                            PSTypeName   = 'DbaToolbox.SearchResult'
                            ComputerName = $server.ComputerName
                            InstanceName = $server.InstanceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.Name
                            Type         = 'SqlModule'
                            SchemaName   = $row.SchemaName
                            ObjectName   = $row.ObjectName
                            ObjectType   = $row.ObjectType
                            MatchContext = $row.Definition
                            SearchString = $SearchString
                        }
                    }
                }
            }

            # --- Agent Job Steps ---
            if ('AgentJobs' -in $Type) {
                Write-Verbose "Searching Agent job steps on $($server.DomainInstanceName)"

                $splatAgentQuery = @{
                    SqlInstance     = $instance
                    Database        = 'msdb'
                    Query           = $agentJobsQuery
                    SqlParameter    = $sqlParam
                    EnableException = $true
                }
                if ($SqlCredential) { $splatAgentQuery['SqlCredential'] = $SqlCredential }

                try {
                    $rows = Invoke-DbaQuery @splatAgentQuery
                } catch {
                    if ($EnableException) { throw }
                    Write-Warning "Find-ServerString: Agent job search failed on $instance : $_"
                    continue
                }

                foreach ($row in $rows) {
                    [PSCustomObject]@{
                        PSTypeName   = 'DbaToolbox.SearchResult'
                        ComputerName = $server.ComputerName
                        InstanceName = $server.InstanceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $row.DBName
                        Type         = 'AgentJob'
                        SchemaName   = $null
                        ObjectName   = "$($row.JobName) / Step $($row.StepID): $($row.StepName)"
                        ObjectType   = 'AgentJobStep'
                        MatchContext = $row.Command
                        SearchString = $SearchString
                    }
                }
            }

            # --- Linked Servers ---
            if ('LinkedServers' -in $Type) {
                Write-Verbose "Searching linked servers on $($server.DomainInstanceName)"

                $splatLinkedQuery = @{
                    SqlInstance     = $instance
                    Query           = $linkedServersQuery
                    SqlParameter    = $sqlParam
                    EnableException = $true
                }
                if ($SqlCredential) { $splatLinkedQuery['SqlCredential'] = $SqlCredential }

                try {
                    $rows = Invoke-DbaQuery @splatLinkedQuery
                } catch {
                    if ($EnableException) { throw }
                    Write-Warning "Find-ServerString: Linked server search failed on $instance : $_"
                    continue
                }

                foreach ($row in $rows) {
                    [PSCustomObject]@{
                        PSTypeName   = 'DbaToolbox.SearchResult'
                        ComputerName = $server.ComputerName
                        InstanceName = $server.InstanceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $null
                        Type         = 'LinkedServer'
                        SchemaName   = $null
                        ObjectName   = $row.LinkedServerName
                        ObjectType   = 'LinkedServer'
                        MatchContext = "Provider=$($row.Provider); DataSource=$($row.DataSource); Location=$($row.Location)"
                        SearchString = $SearchString
                    }
                }
            }
        }
    }

    end {}
}
