# Handoff — SQL Server Troubleshooting Notebook

*Updated: 2026-06-05*

---

## Active Project

**Notebook:** SQL Server Troubleshooting Notebook  
**Type:** Jupyter `.ipynb` with PowerShell kernel (.NET Interactive)  
**Location:** `C:\Users\eric.r\OneDrive - Outdoor Network\source\personal\DbaToolbox`  
**Repo:** `C:\Users\eric.r\OneDrive - Outdoor Network\source\personal\SQL-Server-Operations-Guide` (reference)

---

## Environment

**Instances in parameter block:**
- `GP-ENT-NEW\ENT` — Production clustered (primary)
- `SQL-RPL-NEW\RPL` — Production replication
- `WMS-SQL\ODNWMS` — Production WMS
- `SQL-PMA\ODNPMA` — Production PMA
- `SQL-ENT-TEST\ENT` — Test ENT
- `SQL-RPL-TEST\RPL` — Test replication
- `TEST-WMS-SQL` — Test WMS

**Key databases:** `ODND` (main GP), `DBAOps` (tooling/monitoring on every instance)  
**Auth:** Windows auth. Never pass `-Credential` unless explicitly needed.

---

## Notebook Sections (completed)

| Section | Status | Notes |
|---|---|---|
| Header | ✅ | |
| Navigation anchors | ✅ | Added at top |
| Parameters | ✅ | ArrayList pattern with env groups |
| Prerequisites | ✅ | dbatools version + sp_WhoIsActive + FRK check |
| Blocking & Lock Analysis | ✅ | Quick check + full chain + kill (commented) |
| Wait Statistics | ✅ | `Get-DbaWaitStatistic` + sp_BlitzFirst (commented/optional) |
| Long-Running Queries | ✅ | Via `Invoke-DbaWhoIsActive` — elapsed_time filter needs revisit |
| Open Transactions | ✅ | `Invoke-DbaWhoIsActive -GetTransactionInfo -ShowSleepingSpids 2` |
| Deadlock Analysis | ✅ | Queries `DBAOps.trace.DeadlockHistory` |
| Top Resource-Consuming Queries | ✅ | CPU, Reads, Writes — plan cache, with `$ExcludeInternalQueries` switch |
| TempDB Contention | ✅ | PAGELATCH waits + `Test-DbaTempDbConfig` + file detail + session usage + version store |
| Database File Space | ✅ | Disk + DB summary + file detail via `Get-DbaDbFile` |
| Agent Job Status | 🔄 | Failed jobs cell written, long-running cell written — not yet tested |

---

## Parameter Block Variables

```powershell
$SqlInstances                # ArrayList of pscustomobject @{Instance='...'}
$BlockingThresholdSeconds    # = 5
$TopN                        # = 25
$Credential                  # = $null (not passed to cmdlets)
$ExcludeInternalQueries      # = $false
$DiskSpaceThresholdPct       # = 90
$JobHistoryHours             # = 24
$JobRunningMultiplier        # = 2
$ExcludeJobs                 # = @()
```

---

## Deadlock Capture Infrastructure

**Deployed on all instances:**
- `DBAOps.trace.DeadlockHistory` table (exists)
- `DBAOps.trace.CaptureDeadlocks` proc — reads `system_health` ring buffer
- `DBAOps.trace.CleanupDeadlockHistory` proc — retention 90 days
- Agent job: `DBAOps - Capture Deadlocks` — every 5 minutes, step 1 capture, step 2 cleanup

**No custom XE session needed** — uses `system_health` which is always on.

---

## Agent Job Naming Convention

All jobs must be prefixed: `DBAOps - <Name>`

---

## Open Items / Known Issues

1. **Long-Running Queries** — `elapsed_time` from `sp_WhoIsActive` is a formatted string, not numeric. The `$BlockingThresholdSeconds * 1000` comparison won't work as-is. Needs a proper string-to-timespan parse before filtering.
2. **Agent Job Status — long-running cell** — not yet tested. Uses `LastRunDate` as start time proxy for running jobs since SMO Job objects don't expose start time directly.
3. **TempDB unequal file sizes** on `GP-ENT-NEW\ENT` — `temp4`, `temp5`, `temp8` are 8MB while others are 4-8GB. Known issue, flagged to user.
4. **ODND data file** on `GP-ENT-NEW\ENT` — `GPSODNDDat.mdf` autogrowth set to `0 MB` — investigate.

---

## Reference Repos

- Personal ops guide: https://github.com/eritzie/SQL-Server-Operations-Guide
- dbatools docs: https://docs.dbatools.io
- dbatools source: https://github.com/dataplat/dbatools

---

## Next Steps

1. Test Agent Job Status cells
2. Fix Long-Running Queries elapsed_time comparison
3. Consider saving notebook to `DbaToolbox` repo and committing
4. Consider adding replication monitoring as a separate notebook