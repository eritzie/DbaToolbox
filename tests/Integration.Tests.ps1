#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

<#
    Live integration tests — run every exported function against a real SQL Server.

    Gated on an environment variable so no real server names live in this repo:

        $env:DBATOOLBOX_TEST_INSTANCE = '<safe dev/test instance>'
        Invoke-Pester .\tests\Integration.Tests.ps1 -Output Detailed

    All checks are read-only except three deliberately induced, self-cleaning test
    conditions: a WAITFOR DELAY session, a two-session blocking pair on a global temp
    table, and one bad-password login attempt. Only point this at a dev/test instance.
#>

BeforeDiscovery {
    $script:integrationTarget = $env:DBATOOLBOX_TEST_INSTANCE
}

Describe 'DbaToolbox live integration' -Tag 'Integration' -Skip:(-not $script:integrationTarget) {

    BeforeAll {
        Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force

        $instance = $env:DBATOOLBOX_TEST_INSTANCE
        $server   = Connect-DbaInstance -SqlInstance $instance

        # Feature detection for conditional blocks
        $script:hasDbaOps = @(Get-DbaDatabase -SqlInstance $server -Database 'DBAOps').Count -gt 0
        $script:hasAg     = $server.IsHadrEnabled -and @(Get-DbaAgReplica -SqlInstance $server -WarningAction SilentlyContinue).Count -gt 0
        $script:hasRepl   = $false
        try { $script:hasRepl = @(Get-DbaReplPublication -SqlInstance $server -EnableException -WarningAction SilentlyContinue).Count -gt 0 } catch { }

        # Raw async connection helper for induced sessions (dbatools loads Microsoft.Data.SqlClient)
        function script:New-RawConnection {
            $connString = "Server=$($env:DBATOOLBOX_TEST_INSTANCE);Integrated Security=SSPI;TrustServerCertificate=True;Application Name=DbaToolboxIntegration"
            $conn = New-Object Microsoft.Data.SqlClient.SqlConnection $connString
            $conn.Open()
            $conn
        }
    }

    Context 'Get-ConnectionSummary' {
        It 'Returns at least one connection profile with populated columns' {
            $result = @(Get-ConnectionSummary -SqlInstance $instance)
            $result.Count | Should -BeGreaterThan 0
            $result[0].ConnectionCount | Should -BeGreaterOrEqual 1
            $result[0].LoginName | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-DatabaseSize' {
        It 'Returns summary rows with positive sizes' {
            $result = @(Get-DatabaseSize -SqlInstance $instance)
            $result.Count | Should -BeGreaterThan 0
            ($result | Where-Object TotalSizeMB -le 0) | Should -BeNullOrEmpty
        }

        It 'Returns file rows with populated AutoGrowth when -IncludeFiles is set' {
            $files = Get-DatabaseSize -SqlInstance $instance -IncludeFiles |
                Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.DatabaseFile' }
            @($files).Count | Should -BeGreaterThan 0
            ($files | Where-Object { -not $_.AutoGrowth }) | Should -BeNullOrEmpty
        }
    }

    Context 'Get-TempdbConfig' {
        It 'Returns one TempdbFile row per tempdb file' {
            $fileCount = (Invoke-DbaQuery -SqlInstance $server -Database tempdb -Query 'SELECT COUNT(*) AS C FROM sys.database_files;').C
            $rows = Get-TempdbConfig -SqlInstance $instance |
                Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.TempdbFile' }
            @($rows).Count | Should -Be $fileCount
        }
    }

    Context 'Get-VersionStoreUsage' {
        It 'Returns exactly one VersionStoreTotal row (multi-file tempdb regression)' {
            $totals = Get-VersionStoreUsage -SqlInstance $instance |
                Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.VersionStoreTotal' }
            @($totals).Count | Should -Be 1
        }
    }

    Context 'Get-TopQuery' {
        It 'Returns plan cache rows with populated QueryText' {
            $result = @(Get-TopQuery -SqlInstance $instance -Top 5)
            $result.Count | Should -BeGreaterThan 0
            $result[0].QueryText | Should -Not -BeNullOrEmpty
        }

        It 'Ranks by logical reads without error' {
            { Get-TopQuery -SqlInstance $instance -SortBy LogicalReads -Top 5 -EnableException } | Should -Not -Throw
        }
    }

    Context 'Get-WaitStatistic' {
        It 'Returns cumulative waits with categories' {
            $result = @(Get-WaitStatistic -SqlInstance $instance)
            $result.Count | Should -BeGreaterThan 0
            $result[0].WaitType | Should -Not -BeNullOrEmpty
        }

        It 'Sample mode runs without error' {
            { Get-WaitStatistic -SqlInstance $instance -SampleSeconds 3 -EnableException | Out-Null } | Should -Not -Throw
        }
    }

    Context 'Get-LongRunningQuery (induced WAITFOR)' {
        BeforeAll {
            $script:waitConn = New-RawConnection
            $cmd = $script:waitConn.CreateCommand()
            $cmd.CommandText = "WAITFOR DELAY '00:00:30'"
            $cmd.CommandTimeout = 60
            $script:waitTask = $cmd.ExecuteNonQueryAsync()
            Start-Sleep -Seconds 8
        }

        AfterAll {
            if ($script:waitConn) { $script:waitConn.Close() }
        }

        It 'Detects the induced long-running session with a sane ElapsedTime' {
            $result = Get-LongRunningQuery -SqlInstance $instance -ThresholdSeconds 5 |
                Where-Object SqlText -like '*WAITFOR DELAY*'
            $result | Should -Not -BeNullOrEmpty
            $result[0].ElapsedTime.TotalSeconds | Should -BeGreaterThan 5
            $result[0].ElapsedTime.TotalSeconds | Should -BeLessThan 120
        }
    }

    Context 'Get-BlockingSession and Get-OpenTransaction (induced block)' {
        BeforeAll {
            # Session 1: open transaction holding an X lock on a global temp table
            $script:blockerConn = New-RawConnection
            $setup = $script:blockerConn.CreateCommand()
            $setup.CommandText = @'
CREATE TABLE ##DbaToolboxBlockTest (Id int PRIMARY KEY, Payload varchar(50));
INSERT INTO ##DbaToolboxBlockTest VALUES (1, 'initial');
BEGIN TRAN;
UPDATE ##DbaToolboxBlockTest SET Payload = 'locked' WHERE Id = 1;
'@
            $null = $setup.ExecuteNonQuery()

            # Session 2: blocked reader (async — it cannot complete until session 1 commits)
            $script:blockedConn = New-RawConnection
            $reader = $script:blockedConn.CreateCommand()
            $reader.CommandText = 'SELECT Payload FROM ##DbaToolboxBlockTest WHERE Id = 1;'
            $reader.CommandTimeout = 90
            $script:blockedTask = $reader.ExecuteScalarAsync()
            Start-Sleep -Seconds 5
        }

        AfterAll {
            if ($script:blockerConn) {
                try {
                    $cleanup = $script:blockerConn.CreateCommand()
                    $cleanup.CommandText = 'ROLLBACK TRAN; DROP TABLE ##DbaToolboxBlockTest;'
                    $null = $cleanup.ExecuteNonQuery()
                } catch { }
                $script:blockerConn.Close()
            }
            if ($script:blockedConn) { $script:blockedConn.Close() }
        }

        It 'Detects the induced blocking chain with populated WaitInfo' {
            $result = @(Get-BlockingSession -SqlInstance $instance)
            $result.Count | Should -BeGreaterOrEqual 2
            $blocked = $result | Where-Object { $_.BlockingSessionId -gt 0 }
            $blocked | Should -Not -BeNullOrEmpty
            $blocked[0].WaitInfo | Should -Match 'LCK_'
        }

        It 'Detects the blocker as an open transaction' {
            $result = Get-OpenTransaction -SqlInstance $instance |
                Where-Object { $_.OpenTranCount -gt 0 -and $_.SqlText -like '*DbaToolboxBlockTest*' }
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-FailedLogin (induced bad password)' {
        BeforeAll {
            $badPassword = ConvertTo-SecureString 'definitely-wrong-password' -AsPlainText -Force
            $badCred     = New-Object System.Management.Automation.PSCredential ('dbatoolbox_bogus_login', $badPassword)
            try {
                $null = Connect-DbaInstance -SqlInstance $instance -SqlCredential $badCred -ConnectTimeout 5
            } catch { }
            Start-Sleep -Seconds 2
        }

        It 'Surfaces the induced login failure with parsed columns' {
            $result = Get-FailedLogin -SqlInstance $instance -HoursBack 1 |
                Where-Object Login -eq 'dbatoolbox_bogus_login'
            $result | Should -Not -BeNullOrEmpty
            $result[0].FailureCount | Should -BeGreaterOrEqual 1
            $result[0].Reason | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Agent job functions' {
        It 'Get-FailedJob runs without error' {
            { Get-FailedJob -SqlInstance $instance -EnableException | Out-Null } | Should -Not -Throw
        }

        It 'Get-LongRunningJob runs without error' {
            { Get-LongRunningJob -SqlInstance $instance -EnableException | Out-Null } | Should -Not -Throw
        }
    }

    Context 'Get-TempdbContention' {
        It 'Runs without error' {
            { Get-TempdbContention -SqlInstance $instance -EnableException | Out-Null } | Should -Not -Throw
        }
    }

    Context 'Get-DeadlockHistory (requires DBAOps)' {
        It 'Returns summary rows without error' {
            if (-not $script:hasDbaOps) {
                Set-ItResult -Skipped -Because 'DBAOps database not present on target'
                return
            }
            { Get-DeadlockHistory -SqlInstance $instance -Summary -EnableException | Out-Null } | Should -Not -Throw
        }
    }

    Context 'Get-AgHealth' {
        It 'Returns replica health when an AG exists' {
            if (-not $script:hasAg) {
                Set-ItResult -Skipped -Because 'no availability group on target'
                return
            }
            $result = Get-AgHealth -SqlInstance $instance |
                Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.AgReplicaHealth' }
            @($result).Count | Should -BeGreaterThan 0
        }

        It 'Runs without error on any instance' {
            { Get-AgHealth -SqlInstance $instance -EnableException | Out-Null } | Should -Not -Throw
        }
    }

    Context 'Get-ReplicationStatus' {
        It 'Returns publication rows when replication exists' {
            if (-not $script:hasRepl) {
                Set-ItResult -Skipped -Because 'no replication on target'
                return
            }
            $result = Get-ReplicationStatus -SqlInstance $instance |
                Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.ReplPublication' }
            @($result).Count | Should -BeGreaterThan 0
        }

        It 'Runs without error on any instance' {
            { Get-ReplicationStatus -SqlInstance $instance | Out-Null } | Should -Not -Throw
        }
    }

    Context 'Find-ServerString' {
        It 'Runs a linked-server search without error' {
            { Find-ServerString -SqlInstance $instance -SearchString 'DbaToolboxProbe' -Type LinkedServers -EnableException | Out-Null } | Should -Not -Throw
        }
    }
}
