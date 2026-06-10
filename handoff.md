# Handoff — DbaToolbox Function Build

*Updated: 2026-06-09*

---

## Active Project

**Module:** DbaToolbox  
**Location:** `C:\Users\eric.r\OneDrive - Outdoor Network\source\personal\DbaToolbox`  
**Status:** 12 new functions built, tested, and ScriptAnalyzer-clean.

---

## What Was Done This Session

All 12 functions from the troubleshooting notebook have been implemented:

| Function | File | Test | Status |
|---|---|---|---|
| `Get-BlockingSession` | functions\Get-BlockingSession.ps1 | tests\Get-BlockingSession.Tests.ps1 | ✅ |
| `Get-ConnectionSummary` | functions\Get-ConnectionSummary.ps1 | tests\Get-ConnectionSummary.Tests.ps1 | ✅ |
| `Get-DatabaseSize` | functions\Get-DatabaseSize.ps1 | tests\Get-DatabaseSize.Tests.ps1 | ✅ |
| `Get-DeadlockHistory` | functions\Get-DeadlockHistory.ps1 | tests\Get-DeadlockHistory.Tests.ps1 | ✅ |
| `Get-FailedJob` | functions\Get-FailedJob.ps1 | tests\Get-FailedJob.Tests.ps1 | ✅ |
| `Get-LongRunningJob` | functions\Get-LongRunningJob.ps1 | tests\Get-LongRunningJob.Tests.ps1 | ✅ |
| `Get-LongRunningQuery` | functions\Get-LongRunningQuery.ps1 | tests\Get-LongRunningQuery.Tests.ps1 | ✅ |
| `Get-OpenTransaction` | functions\Get-OpenTransaction.ps1 | tests\Get-OpenTransaction.Tests.ps1 | ✅ |
| `Get-TempdbConfig` | functions\Get-TempdbConfig.ps1 | tests\Get-TempdbConfig.Tests.ps1 | ✅ |
| `Get-TempdbContention` | functions\Get-TempdbContention.ps1 | tests\Get-TempdbContention.Tests.ps1 | ✅ |
| `Get-TopQuery` | functions\Get-TopQuery.ps1 | tests\Get-TopQuery.Tests.ps1 | ✅ |
| `Get-VersionStoreUsage` | functions\Get-VersionStoreUsage.ps1 | tests\Get-VersionStoreUsage.Tests.ps1 | ✅ |

**DbaToolbox.psd1** — all 12 functions added to `FunctionsToExport`.  
**DbaToolbox.Format.ps1xml** — 18 new `View` blocks added (one per output PSTypeName).  
**Pester:** 100/100 tests pass.  
**ScriptAnalyzer:** 0 warnings across all new functions.

---

## Key Design Decisions Made This Session

### elapsed_time fix (open issue #1)
`Get-LongRunningQuery` now parses `elapsed_time` via `[timespan]::TryParse()`. Sessions where the string cannot be parsed are silently skipped. The notebook cell that used `($_.elapsed_time -as [int]) -gt threshold` was broken — the `[timespan]` parse is the fix.

### Get-LongRunningJob (open issue #2)
Implemented as designed. `LastRunDate` is used as a start-time proxy. Documented in `.DESCRIPTION`. Also fixed a PS 7+ compatibility issue: `Measure-Object { scriptblock }` was changed to `ForEach-Object { ... } | Measure-Object` for PS 5.1 compatibility.

### Get-DeadlockHistory parameter sets
Three modes implemented via `[CmdletBinding(DefaultParameterSetName = 'Default')]`:
- Default: returns `DbaToolbox.DeadlockEvent`
- `-Summary`: returns `DbaToolbox.DeadlockSummary`
- `-Id [Nullable[int]]`: returns `DbaToolbox.DeadlockGraph`

### Get-TempdbConfig / Get-VersionStoreUsage multi-type output
Both functions emit multiple PSTypeName types from a single call. Callers can filter with `Where-Object { $_.PSObject.TypeNames[0] -eq 'TypeName' }`.

### Get-VersionStoreUsage graceful degradation
`sys.dm_tran_version_store_space_usage` (SQL 2016 SP2+) errors are caught and a warning is emitted without aborting — `DbaToolbox.VersionStoreTotal` and `DbaToolbox.SnapshotIsolationDatabase` rows are still returned.

---

## Output Types Added

| PSTypeName | Emitting Function |
|---|---|
| `DbaToolbox.BlockingSession` | Get-BlockingSession |
| `DbaToolbox.ConnectionSummary` | Get-ConnectionSummary |
| `DbaToolbox.DatabaseSize` | Get-DatabaseSize |
| `DbaToolbox.DatabaseFile` | Get-DatabaseSize -IncludeFiles |
| `DbaToolbox.DeadlockEvent` | Get-DeadlockHistory (default) |
| `DbaToolbox.DeadlockSummary` | Get-DeadlockHistory -Summary |
| `DbaToolbox.DeadlockGraph` | Get-DeadlockHistory -Id |
| `DbaToolbox.FailedJob` | Get-FailedJob |
| `DbaToolbox.LongRunningJob` | Get-LongRunningJob |
| `DbaToolbox.LongRunningQuery` | Get-LongRunningQuery |
| `DbaToolbox.OpenTransaction` | Get-OpenTransaction |
| `DbaToolbox.TempdbBestPractice` | Get-TempdbConfig |
| `DbaToolbox.TempdbFile` | Get-TempdbConfig |
| `DbaToolbox.TempdbContention` | Get-TempdbContention |
| `DbaToolbox.TopQuery` | Get-TopQuery |
| `DbaToolbox.VersionStoreTotal` | Get-VersionStoreUsage |
| `DbaToolbox.VersionStoreUsage` | Get-VersionStoreUsage |
| `DbaToolbox.SnapshotIsolationDatabase` | Get-VersionStoreUsage |

---

## Open Items

1. **Integration testing** — none of the 12 new functions have been run against a live SQL Server. The Pester tests use mocks. Run against `SQL-DEV-01` or `localhost` before deploying to production.
2. **Get-LongRunningJob StartDate accuracy** — `LastRunDate` is an SMO approximation. If a more accurate start time matters, investigate whether `msdb.dbo.sysjobactivity.start_execution_date` can be queried directly.
3. **TempDB unequal file sizes on GP-ENT-NEW\ENT** — carried forward from prior session; `temp4`, `temp5`, `temp8` are 8MB while others are 4–8GB.
4. **ODND data file autogrowth on GP-ENT-NEW\ENT** — `GPSODNDDat.mdf` autogrowth = 0 MB; needs investigation.
5. **Replication monitoring** — consider a separate notebook/function set for replication health.

---

## Environment Reminder

| Alias | Role | Safe for Writes |
|---|---|---|
| GP-ENT-NEW\ENT | Production AG primary | NO |
| SQL-RPL-NEW\RPL | Production replication | NO |
| SQL-PMA\ODNPMA | Production PMA | NO |
| localhost | SQL 2025 local | YES |
| SQL-DEV-01 | Dev/test | YES |
