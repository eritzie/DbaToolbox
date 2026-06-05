# Session Feedback & Corrections

*Reload at the start of each session. Treat as standing rules that override default behavior.*

---

## dbatools Rules

- **ALWAYS verify dbatools cmdlet names against https://docs.dbatools.io or https://github.com/dataplat/dbatools before using them.** Never guess or infer cmdlet names. This was violated multiple times in this session and caused wasted debugging cycles.
- Confirmed real cmdlets used in this session: `Invoke-DbaWhoIsActive`, `Get-DbaWaitStatistic`, `Get-DbaDbStoredProcedure`, `Get-DbaDbFile`, `Get-DbaDiskSpace`, `Get-DbaTempdbUsage`, `Test-DbaTempDbConfig`, `Get-DbaRunningJob`, `Get-DbaAgentJobHistory`, `Stop-DbaProcess`, `Install-DbaWhoIsActive`, `Install-DbaFirstResponderKit`
- Fake cmdlets I invented that do not exist: `Get-DbaStoredProcedure`, `Get-DbaProcess` (exists but properties differ from what I assumed)

---

## Corrections Made by User

### Jupyter / .NET Interactive

- `Format-Table` inside a `foreach` loop crashes the .NET Interactive PowerShell kernel when output spans multiple iterations. Fix: pipe through `Out-String -Width N` after `Format-Table`, or use `Format-Table | Out-String | Write-Host` pattern.
- PowerShell kernel for Jupyter requires .NET Interactive (`dotnet tool install -g Microsoft.dotnet-interactive` + `dotnet interactive jupyter install`). It does NOT appear at the top level of the kernel picker — it appears under **Jupyter Kernel...** submenu.
- `-Credential $Credential` causes errors when using Windows auth. Remove it from all dbatools calls unless SQL auth is explicitly needed.

### dbatools Cmdlet Errors

- `Get-DbaStoredProcedure` does not exist. Correct cmdlet is `Get-DbaDbStoredProcedure`.
- I invented `-GetTaskInfo` and `-FindBlockLeaders` as parameters without verifying — both happen to be real, but the crash was caused by `Format-Table` conflict, not the parameters.
- `Get-DbaProcess` property `BlockingSpid` — user flagged that the return object may not match what I assumed. Always check actual property names.
- `Get-DbaRunningJob` returns SMO `Agent.Job` objects. Job name is `Name`, not `JobName`. No `StartDate` property — use `LastRunDate` as proxy.
- `Get-DbaAgentJobHistory` output uses `Job` (not `JobName`) as the display property name.

### T-SQL Issues

- `FILEPROPERTY()` only works in the context of the database the file belongs to. Running it against `sys.master_files` from `master` context returns NULL for all databases except master. Use `Get-DbaDbFile` instead, or switch database context per database.
- `unversioned_reserved_page_count` in `sys.dm_db_file_space_usage` was added in SQL Server 2019. Remove it for cross-version compatibility.
- `sys.dm_tran_version_store_space_usage` requires SQL Server 2016 SP2+.

### PowerShell Issues

- `Get-DbaDiskSpace` returns `Capacity` and `Free` as dbatools `[dbasize]` objects, not plain numbers. Cast with `[long]$_.Capacity` not `$_.Capacity.Bytes`.
- `Get-DbaDbFile` size properties (`Size`, `UsedSpace`, `AvailableSpace`) are also `[dbasize]` objects. Cast with `[long]$_.Size`, not `[long]$_.Size.Bytes`.
- `Invoke-DbaWhoIsActive` columns like `blocking_session_id` and `blocked_session_count` return as strings, not integers. Use `-as [int]` for comparisons, not `-gt` directly.
- `elapsed_time` from `sp_WhoIsActive` is a formatted string (`0:00:05.123`), not milliseconds.
- Add `-As PSObject` to `Invoke-DbaWhoIsActive` calls for cleaner property handling.

### Architectural / Design Corrections

- MSSQL kernel notebooks support only a single server connection — cannot loop across multiple servers. Switched to PowerShell kernel + dbatools for multi-server support.
- `sp_BlitzFirst` took 2+ minutes to return. Marked as commented-out/optional in the notebook with a warning.
- Warning blocks listing threshold violations were dropped — the table output itself is sufficient.
- Agent job naming convention: all jobs must start with **DBAOps -** (e.g., `DBAOps - Capture Deadlocks`).
- `sp_BlitzLock` is for deadlock analysis, not blocking. Blocking uses `sp_WhoIsActive` + `sp_BlitzWho`.
- `trace.CaptureDeadlocks` already uses `system_health` — no custom XE session needed.

---

## Stated Preferences

### Notebook Structure
- One cell at a time, test before moving on.
- Markdown cells need substantive descriptions, not just one-liners.
- Section headers get a table where useful (e.g., prerequisites table listing tools and purposes).
- Navigation anchor links at the top of the notebook.
- Parameter block uses the `ArrayList` + `pscustomobject` pattern with commented environment groups, not a simple array.
- `$Credential = $null` kept in parameter block for future use but not passed to cmdlets by default.

### Code Style
- `Out-String -Width 512` (or higher) after `Format-Table` to prevent .NET Interactive formatting conflicts.
- `Write-Host` with `-ForegroundColor Cyan` for instance headers, `Green` for clean results, `Red` for warnings.
- Commented-out kill/destructive operations with clear instructions above them.
- `WHERE 1 = 1` pattern for dynamic filter appending in SQL strings.

### Output Preferences
- Drop warning summary blocks — rely on the table alone.
- `Format-Table -AutoSize -Wrap` for wide output.
- `Out-String -Width 1024` or higher for wide tables.

### SQL Server / DBAOps Standards
- All Agent jobs prefixed with `DBAOps -`
- Retention for deadlock history: 90 days
- Schedule name reuse: use `schedule_id` not `schedule_name` when attaching to avoid duplicate name errors
- `DBAOps` database exists on all managed instances

### Excluded Query Patterns (when `$ExcludeInternalQueries = $true`)
- `#XEStaging`, `dm_xe_session`, `ring_buffer`, `target_data`
- `dm_exec_query_stats` (self-referential)
- `sp_WhoIsActive`, `sp_Blitz%`
- `sysschedules`, `sysjobhistory`
- `tmp_replication_status`, `#tmp%`

---

## Behavioral Notes (all sessions)

- User answers their own architectural questions quickly. Surface tradeoffs, then stop.
- "I don't think X returns what you think it does" = go verify before defending.
- When user says something isn't working, believe them and diagnose — don't defend the original code.
- Test one cell at a time. Don't batch multiple untested cells.
- Don't use `Format-Table` without `Out-String` in any loop across multiple servers.
- Always check dbatools docs before writing any dbatools code. No exceptions.

---

*Last updated: 2026-06-05*