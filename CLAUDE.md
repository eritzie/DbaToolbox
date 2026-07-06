# DbaToolbox

Personal PowerShell module complementing dbatools for SQL Server DBA workflows.
Not affiliated with dbatools. Requires dbatools >= 2.0 and PowerShell 5.1+.

## Session Initialization

At the start of every session, read these two files before doing anything else:

1. `feedback.md` — corrections, stated preferences, and behavioral rules. Treat as standing
   instructions that override defaults.
2. `handoff.md` — current project state, open issues, decisions made, next steps.

If either file fails to load, say so immediately before proceeding.

At the end of any session where decisions were made or work progressed, emit an updated
`handoff.md`. Update `feedback.md` if new corrections or preferences surfaced.

## Project structure

```
DbaToolbox/
├── DbaToolbox.psd1            Module manifest — add new exports here
├── DbaToolbox.psm1            Entry point — dot-sources functions\ automatically
├── DbaToolbox.Format.ps1xml   Default table view for output types
├── functions/                 One file per exported cmdlet
└── tests/                     One Pester 5 test file per cmdlet
```

## Adding a new function

1. Create `functions\Verb-Noun.ps1` — use `functions\Find-ServerString.ps1` as the template.
2. Add the function name to `FunctionsToExport` in `DbaToolbox.psd1`.
3. Add a `View` block to `DbaToolbox.Format.ps1xml` for the new output type.
4. Create `tests\Verb-Noun.Tests.ps1` — mirror the test structure in `tests\Find-ServerString.Tests.ps1`.

## Naming conventions

- No module prefix on function nouns — this is not dbatools. `Find-ServerString`, not `Find-DbaServerString`.
- Use only approved PS verbs: `Get-Verb` to verify before choosing.
- Noun describes the SQL Server concept, not the operation.
- Output type names follow the pattern `DbaToolbox.<Noun>` — e.g., `DbaToolbox.SearchResult`.

## PowerShell conventions

- `[DbaInstanceParameter[]]` for `$SqlInstance` — always, no exceptions.
- `-EnableException [switch]` — always include. On a per-instance failure: `if ($EnableException) { throw } else { Write-Warning ...; continue }`.
  **Never call `Stop-Function`** — it is a private dbatools alias not available to external modules.
- `Write-Message -Level Verbose` for progress output. PSFramework is available when dbatools is loaded.
- Parameterized SQL via `Invoke-DbaQuery -SqlParameter @{ Key = $Value }` — never interpolate user input into query strings.
- No `Out-GridView`, no `Format-*` inside functions — callers decide presentation.
- `SupportsShouldProcess` only on cmdlets that write or delete data.

## T-SQL conventions

- Schema-qualify all objects: `dbo.TableName`.
- ISO 8601 date literals: `'2025-01-31'`.
- `CHARINDEX(@Pattern, column) > 0` for string presence checks — consistent, readable, parameterizable.
- Add `SET NOCOUNT ON` if the query is ever wrapped in a stored procedure.

## Output types

Each cmdlet defines its own `[PSCustomObject]` shape and registers a `PSTypeName`.
The Format.ps1xml controls what columns appear in default table output. All properties
remain accessible on the object — the format file only controls default display width/order.

Common properties every output object should include:

| Property     | Source                           |
|--------------|----------------------------------|
| ComputerName | `$server.ComputerName`           |
| InstanceName | `$server.InstanceName`           |
| SqlInstance  | `$server.DomainInstanceName`     |

## Testing

```powershell
# Run all tests
Invoke-Pester .\tests\ -Output Detailed

# Run a single file
Invoke-Pester .\tests\Find-ServerString.Tests.ps1 -Output Detailed
```

Tests mock `Connect-DbaInstance`, `Get-DbaDatabase`, and `Invoke-DbaQuery` inside
`InModuleScope DbaToolbox` so no live SQL Server is required for unit tests.

## Linting

```powershell
Invoke-ScriptAnalyzer -Path .\functions\ -Recurse -Severity Warning
```

PSScriptAnalyzer must return no warnings before a function is considered production-ready.

## Quick start

```powershell
Import-Module .\DbaToolbox.psd1 -Force

Find-ServerString -SqlInstance 'SQL01\INST' -SearchString 'oldserver' |
    Format-Table -AutoSize

# Scope to one target type
Find-ServerString -SqlInstance 'SQL01\INST' -SearchString 'oldserver' -Type AgentJobs

# Multi-instance via pipeline
'SQL01', 'SQL02' | Find-ServerString -SearchString 'oldserver'

# Verbose shows which databases are being scanned
Find-ServerString -SqlInstance 'SQL01\INST' -SearchString 'oldserver' -Verbose
```
