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
| ComputerName | Host name of the SQL Server                             |
| InstanceName | SQL Server instance name                                |
| SqlInstance  | Fully qualified instance name                           |
| Database     | Database name; `$null` for server-level results         |
| Type         | `SqlModule`, `AgentJob`, or `LinkedServer`              |
| SchemaName   | Populated for `SqlModule` results only                  |
| ObjectName   | Procedure/view/job name/linked server name              |
| ObjectType   | e.g. `SQL_STORED_PROCEDURE`, `AgentJobStep`             |
| MatchContext | Full definition or command text (hidden in table view)  |
| SearchString | The search term (hidden in table view)                  |

`MatchContext` and `SearchString` are on the object but hidden from the default table
display. Access them with `Select-Object *` or reference them directly.

Every cmdlet below also emits the common `ComputerName`, `InstanceName`, and `SqlInstance`
properties (see [CLAUDE.md](CLAUDE.md#output-types)) — omitted from the tables below.

### `Get-AgHealth`

Returns Availability Group replica and database synchronization health.

```
Get-AgHealth
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-AvailabilityGroup <string[]>]
    [-EnableException]
```

```powershell
Get-AgHealth -SqlInstance 'SQL01'
```

Emits two related types — filter on `PSTypeName` to process them separately.

`DbaToolbox.AgReplicaHealth`

| Property              | Notes                        |
|-----------------------|-------------------------------|
| AvailabilityGroup     | AG name                       |
| ReplicaName           |                                |
| Role                  | Primary / Secondary           |
| SynchronizationState  |                                |
| AvailabilityMode      |                                |
| FailoverMode          |                                |

`DbaToolbox.AgDatabaseHealth`

| Property              | Notes                         |
|-----------------------|--------------------------------|
| ReplicaName           |                                 |
| DatabaseName          |                                 |
| SynchronizationState  |                                 |
| IsSuspended           | bool                            |
| LogSendQueueKB        |                                 |
| RedoQueueKB           |                                 |
| EstimatedDataLossSec  | seconds                         |
| LastCommitTime        |                                 |

### `Get-BlockingSession`

Returns sessions involved in blocking chains.

```
Get-BlockingSession
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-Detailed]
    [-EnableException]
```

```powershell
Get-BlockingSession -SqlInstance 'SQL01'
```

`DbaToolbox.BlockingSession`

| Property             | Notes                                                          |
|----------------------|------------------------------------------------------------------|
| SessionId            |                                                                    |
| BlockingSessionId    |                                                                    |
| BlockedSessionCount  |                                                                    |
| WaitInfo             | raw sp_WhoIsActive `wait_info` string, e.g. `(32440753ms)LCK_M_S` |
| Locks / SqlCommand   | only populated with `-Detailed`                                  |

### `Get-ConnectionSummary`

Returns active sessions grouped by database, login, host, program, and state.

```
Get-ConnectionSummary
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-Database <string>]
    [-Login <string>]
    [-HostName <string>]
    [-EnableException]
```

```powershell
Get-ConnectionSummary -SqlInstance 'SQL01'
```

`DbaToolbox.ConnectionSummary`

| Property         | Notes                                        |
|------------------|-------------------------------------------------|
| ConnectionCount  | count of sessions sharing this grouped profile   |
| Command          | `$null` for idle sessions (normal)               |

### `Get-DatabaseSize`

Returns database size summary and, optionally, per-file detail.

```
Get-DatabaseSize
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-Database <string[]>]
    [-IncludeFiles]
    [-EnableException]
```

```powershell
Get-DatabaseSize -SqlInstance 'SQL01'
```

`DbaToolbox.DatabaseSize` — `TotalSizeMB`, `UsedMB`, `FreeMB`, `UsedPct`.

`DbaToolbox.DatabaseFile` (only with `-IncludeFiles`)

| Property    | Notes                                                                          |
|-------------|-----------------------------------------------------------------------------------|
| AutoGrowth  | trailing `*` = percentage-based growth; `Disabled` = growth is 0; else next-growth size in MB |

### `Get-DeadlockHistory`

Returns deadlock events recorded in `DBAOps.trace.DeadlockHistory` (populated every 5
minutes from `system_health` by the `DBAOps - Capture - Deadlocks` Agent job).

```
Get-DeadlockHistory
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-Database <string>]              # default 'DBAOps'
    [-Top <int>]                      # default 25 — ParameterSet 'Default'
    [-Summary]                        # ParameterSet 'Summary'
    [-Id <int>]                       # ParameterSet 'Graph'
    [-EnableException]
```

```powershell
# Most recent events
Get-DeadlockHistory -SqlInstance 'SQL01'

# Frequency by database
Get-DeadlockHistory -SqlInstance 'SQL01' -Summary

# Full deadlock graph XML for one event — paste into SSMS to view the graph
Get-DeadlockHistory -SqlInstance 'SQL01' -Id 42
```

`DbaToolbox.DeadlockEvent` (default) / `DbaToolbox.DeadlockSummary` (`-Summary`) /
`DbaToolbox.DeadlockGraph` (`-Id`, includes the full XML).

### `Get-FailedJob`

Returns every SQL Server Agent job failure within a time window.

```
Get-FailedJob
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-HoursBack <int>]                # default 24
    [-ExcludeJob <string[]>]
    [-EnableException]
```

```powershell
Get-FailedJob -SqlInstance 'SQL01'
```

`DbaToolbox.FailedJob` — `JobName`, `RunDate`, `Duration`, `Message`.

### `Get-FailedLogin`

Returns failed login attempts (error 18456) from the SQL Server error log, grouped by
login, reason, and client address.

```
Get-FailedLogin
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-HoursBack <int>]                # default 24
    [-LogNumber <int[]>]              # default 0 (current log); pass archive numbers too
    [-EnableException]
```

```powershell
Get-FailedLogin -SqlInstance 'SQL01' -HoursBack 168
```

Reads via `xp_readerrorlog` (server-side filtered), not `Get-DbaErrorLog` — SMO streams
the entire log file to the client first, which took nearly an hour against a 2 GB archive.

`DbaToolbox.FailedLogin` — `Login` (`<unknown>` if unparsed), `Reason`, `ClientAddress`,
`FailureCount`, `FirstSeen`, `LastSeen`.

### `Get-LongRunningJob`

Returns SQL Server Agent jobs currently running longer than their historical average.

```
Get-LongRunningJob
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-Multiplier <double>]            # default 2.0
    [-ExcludeJob <string[]>]
    [-EnableException]
```

```powershell
Get-LongRunningJob -SqlInstance 'SQL01'
```

`DbaToolbox.LongRunningJob`

| Property         | Notes                                                            |
|------------------|---------------------------------------------------------------------|
| StartDate        | from `sysjobactivity.start_execution_date`, else `LastRunDate` fallback |
| AvgDuration      | average of successful runs in the last 30 days                       |
| Multiplier       | the job's *actual* multiple of average — not the threshold parameter |

### `Get-LongRunningQuery`

Returns queries that have been executing longer than a threshold.

```
Get-LongRunningQuery
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-ThresholdSeconds <int>]         # default 5
    [-EnableException]
```

```powershell
Get-LongRunningQuery -SqlInstance 'SQL01'
```

`DbaToolbox.LongRunningQuery` — `ElapsedTime` is computed from sp_WhoIsActive's
`start_time`/`collection_time` datetimes, not parsed from its formatted runtime string
(sp_WhoIsActive has no `elapsed_time` column).

### `Get-OpenTransaction`

Returns sessions with open (uncommitted or un-rolled-back) transactions.

```
Get-OpenTransaction
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-EnableException]
```

```powershell
Get-OpenTransaction -SqlInstance 'SQL01'
```

`DbaToolbox.OpenTransaction` — `OpenTranCount` (filtered to > 0), `TranStartTime`,
`TranLogWrites`, `ImplicitTran`.

### `Get-ReplicationStatus`

Returns replication publications and subscriptions. Read-only by design —
`Test-DbaReplLatency` is deliberately not called since it writes tracer tokens.

```
Get-ReplicationStatus
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-EnableException]
```

```powershell
Get-ReplicationStatus -SqlInstance 'SQL01'
```

`DbaToolbox.ReplPublication` (`ArticleCount`, `SubscriptionCount`) and
`DbaToolbox.ReplSubscription` (`SubscriberName`, `SubscriptionDb`, `SubscriptionType`).

### `Get-TempdbConfig`

Returns TempDB best-practice check results and individual file configuration.

```
Get-TempdbConfig
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-EnableException]
```

```powershell
Get-TempdbConfig -SqlInstance 'SQL01'
```

`DbaToolbox.TempdbBestPractice` (from `Test-DbaTempDbConfig`: `Rule`, `CurrentSetting`,
`Recommended`, `IsBestPractice`) and `DbaToolbox.TempdbFile` (`SizeMB`, `FreeMB`,
`AutoGrowth` — trailing `*` = percentage-based growth).

### `Get-TempdbContention`

Returns sessions with active `PAGELATCH` waits on TempDB allocation pages.

```
Get-TempdbContention
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-EnableException]
```

```powershell
Get-TempdbContention -SqlInstance 'SQL01'
```

`DbaToolbox.TempdbContention` — `PageType` classifies `ResourceDescription` into `PFS`,
`GAM`, `SGAM`, or `Other` from the documented page-id intervals.

### `Get-TopQuery`

Returns the top queries from the plan cache, ranked by CPU, logical reads, or logical
writes. Stats are cumulative since the last plan cache flush/restart, not a point-in-time
snapshot — cross-reference with `Get-BlockingSession`/`Get-WaitStatistic` to confirm a
query is an active problem rather than historically expensive.

```
Get-TopQuery
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-Top <int>]                      # default 25
    [-SortBy <string>]                # CPU | LogicalReads | LogicalWrites — default CPU
    [-ExcludeInternal]
    [-EnableException]
```

```powershell
'SQL01', 'SQL02' | Get-TopQuery -ExcludeInternal |
    Select-Object SqlInstance, DatabaseName, TotalCpuSec, QueryText
```

`DbaToolbox.TopQuery` — all three metric sets (CPU/reads/writes) are always populated
regardless of `-SortBy`; `DatabaseName` shows `<ad hoc>` when there's no DB context.

### `Get-VersionStoreUsage`

Returns TempDB version store usage totals, per-database breakdown, and databases with
snapshot isolation enabled.

```
Get-VersionStoreUsage
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-EnableException]
```

```powershell
Get-VersionStoreUsage -SqlInstance 'SQL01'
```

`DbaToolbox.VersionStoreTotal` (one row per instance), `DbaToolbox.VersionStoreUsage`
(per-database — requires SQL Server 2016 SP2+ / build 13.0.5026+, skipped with a warning
on older instances), and `DbaToolbox.SnapshotIsolationDatabase` (`SnapshotState`,
`RCSIEnabled`).

### `Get-WaitStatistic`

Returns SQL Server wait statistics — cumulative since restart, or sampled over an
interval to show current activity.

```
Get-WaitStatistic
    [-SqlInstance] <DbaInstanceParameter[]>
    [-SqlCredential <PSCredential>]
    [-Threshold <int>]                # default 95 — running % cutoff, ignored in sample mode
    [-IncludeIgnorable]
    [-SampleSeconds <int>]            # 1-3600
    [-EnableException]
```

```powershell
# Cumulative, top waits covering 95% of total wait time
Get-WaitStatistic -SqlInstance 'SQL01'

# What the server is waiting on right now — two snapshots 10s apart, diffed
Get-WaitStatistic -SqlInstance 'SQL01' -SampleSeconds 10
```

`DbaToolbox.WaitStatistic` (cumulative, default) vs `DbaToolbox.WaitSample`
(`-SampleSeconds` — delta values over the sample interval, not totals).

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
