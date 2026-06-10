#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-VersionStoreUsage' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-VersionStoreUsage -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Output types' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                # tempdb query → VersionStoreTotal shape
                Mock Invoke-DbaQuery -ParameterFilter { $Database -eq 'tempdb' } {
                    [PSCustomObject]@{
                        VersionStoreMB   = 25
                        UserObjectMB     = 100
                        InternalObjectMB = 10
                    }
                }
                # master queries → first call returns per-db usage, second returns snapshot dbs
                $script:masterCallCount = 0
                Mock Invoke-DbaQuery -ParameterFilter { $Database -eq 'master' } {
                    $script:masterCallCount++
                    if ($script:masterCallCount -eq 1) {
                        [PSCustomObject]@{
                            DatabaseName    = 'AppDB'
                            ReservedMB      = 20
                            ReservedSpaceMB = 20
                        }
                    } else {
                        [PSCustomObject]@{
                            DatabaseName  = 'AppDB'
                            SnapshotState = 'ON'
                            RCSIEnabled   = $true
                        }
                    }
                }
            }
        }

        BeforeEach {
            $script:masterCallCount = 0
        }

        It 'Emits a VersionStoreTotal row' {
            $result = Get-VersionStoreUsage -SqlInstance 'SQL01'
            $totals = $result | Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.VersionStoreTotal' }
            $totals | Should -Not -BeNullOrEmpty
        }

        It 'VersionStoreTotal has required properties' {
            $result = Get-VersionStoreUsage -SqlInstance 'SQL01'
            $row    = $result | Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.VersionStoreTotal' }
            $props  = $row.PSObject.Properties.Name
            $props  | Should -Contain 'SqlInstance'
            $props  | Should -Contain 'VersionStoreMB'
            $props  | Should -Contain 'UserObjectMB'
            $props  | Should -Contain 'InternalObjectMB'
        }

        It 'Emits VersionStoreUsage rows when per-db query succeeds' {
            $result  = Get-VersionStoreUsage -SqlInstance 'SQL01'
            $perDb   = $result | Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.VersionStoreUsage' }
            $perDb   | Should -Not -BeNullOrEmpty
            $perDb.PSObject.Properties.Name | Should -Contain 'DatabaseName'
            $perDb.PSObject.Properties.Name | Should -Contain 'ReservedMB'
        }

        It 'Emits SnapshotIsolationDatabase rows' {
            $result  = Get-VersionStoreUsage -SqlInstance 'SQL01'
            $snapDbs = $result | Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.SnapshotIsolationDatabase' }
            $snapDbs | Should -Not -BeNullOrEmpty
            $snapDbs.PSObject.Properties.Name | Should -Contain 'SnapshotState'
            $snapDbs.PSObject.Properties.Name | Should -Contain 'RCSIEnabled'
        }
    }

    Context 'Handles missing sys.dm_tran_version_store_space_usage gracefully' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Invoke-DbaQuery -ParameterFilter { $Database -eq 'tempdb' } {
                    [PSCustomObject]@{
                        VersionStoreMB   = 5
                        UserObjectMB     = 20
                        InternalObjectMB = 2
                    }
                }
                # Simulate SQL 2016 SP2+ not available — first master call throws
                $script:masterCallCount2 = 0
                Mock Invoke-DbaQuery -ParameterFilter { $Database -eq 'master' } {
                    $script:masterCallCount2++
                    if ($script:masterCallCount2 -eq 1) {
                        throw 'Invalid object name sys.dm_tran_version_store_space_usage'
                    }
                    # Second call (snapshot query) succeeds with empty results
                    @()
                }
            }
        }

        BeforeEach {
            $script:masterCallCount2 = 0
        }

        It 'Writes a warning but does not throw when per-db query fails' {
            { Get-VersionStoreUsage -SqlInstance 'SQL01' -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Still returns VersionStoreTotal when per-db query fails' {
            $result = Get-VersionStoreUsage -SqlInstance 'SQL01' -WarningAction SilentlyContinue
            $totals = $result | Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.VersionStoreTotal' }
            $totals | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Pipeline input' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = $SqlInstance.ComputerName
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = $SqlInstance.ToString()
                    }
                }
                Mock Invoke-DbaQuery { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-VersionStoreUsage | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
