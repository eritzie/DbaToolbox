# DbaToolbox

A personal PowerShell module complementing [dbatools](https://dbatools.io) for SQL Server DBA workflows.

## Requirements

- PowerShell 5.1 or PowerShell 7+
- [dbatools](https://github.com/dataplat/dbatools) >= 2.0

```powershell
Install-Module dbatools -Scope CurrentUser
```

## Installation

**Option A — import directly (development/local use)**

```powershell
Import-Module C:\path\to\DbaToolbox\DbaToolbox.psd1
```

**Option B — copy to your module path (persistent across sessions)**

```powershell
$dest = "$([Environment]::GetFolderPath('MyDocuments'))\PowerShell\Modules\DbaToolbox"
Copy-Item -Path C:\path\to\DbaToolbox -Destination $dest -Recurse
Import-Module DbaToolbox
```

## Cmdlets

### `Find-ServerString`

Searches one or more SQL Server instances for a string across SQL module definitions,
Agent job step commands, and linked server configurations.

```
Find-ServerString
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    -SearchString <string>
    [-Database <string[]>]
    [-ExcludeDatabase <string[]>]
    [-Type <string[]>]               # SqlModules | AgentJobs | LinkedServers
    [-IncludeSystemDatabases]
    [-EnableException]
```

#### Examples

```powershell
# Search all three target types on a single instance
Find-ServerString -SqlInstance 'SQL01\INST' -SearchString 'oldserver'

# Pipeline input — search multiple instances
'SQL01', 'SQL02' | Find-ServerString -SearchString 'oldserver'

# Narrow to one target type
Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' -Type AgentJobs

# Restrict SQL module search to specific databases
Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' `
    -Type SqlModules -Database 'AppDB', 'ReportDB'

# Show verbose progress (which databases are being scanned)
Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' -Verbose

# Pipe to Out-GridView for interactive review
Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' |
    Out-GridView -Title 'Search Results'

# Export to CSV
Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' |
    Export-Csv -Path results.csv -NoTypeInformation
```

#### Output properties

| Property     | Notes                                                   |
|--------------|---------------------------------------------------------|
| SqlInstance  | Instance name                                           |
| Database     | Database name; `$null` for server-level results         |
| Type         | `SqlModule`, `AgentJob`, or `LinkedServer`              |
| SchemaName   | Populated for `SqlModule` results only                  |
| ObjectName   | Procedure/view/job name/linked server name              |
| ObjectType   | e.g. `SQL_STORED_PROCEDURE`, `AgentJobStep`             |
| MatchContext | Full definition or command text (hidden in table view)  |
| SearchString | The search term (hidden in table view)                  |

`MatchContext` and `SearchString` are on the object but hidden from the default table
display. Access them with `Select-Object *` or reference them directly.

## Development

See [CLAUDE.md](CLAUDE.md) for conventions, the function template, and how to add new cmdlets.

```powershell
# Run tests (Pester 5 required, no live SQL Server needed)
Invoke-Pester .\tests\ -Output Detailed

# Lint
Invoke-ScriptAnalyzer -Path .\functions\ -Recurse -Severity Warning

# Validate manifest
Test-ModuleManifest .\DbaToolbox.psd1
```

## License

[MIT](LICENSE)
