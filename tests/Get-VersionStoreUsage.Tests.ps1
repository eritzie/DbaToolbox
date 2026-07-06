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
                        VersionMajor       = 15
                        BuildNumber        = 4280
                    }
                }
                # tempdb query → VersionStoreTotal shape
                Mock Invoke-DbaQuery -RemoveParameterType 'SqlInstance' -ParameterFilter { $Database -eq 'tempdb' } {
                    [PSCustomObject]@{
                        VersionStoreMB   = 25
                        UserObjectMB     = 100
                        InternalObjectMB = 10
                    }
                }
                # master queries → first call returns per-db usage, second returns snapshot dbs
                $script:masterCallCount = 0
                Mock Invoke-DbaQuery -RemoveParameterType 'SqlInstance' -ParameterFilter { $Database -eq 'master' } {
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

    Context 'Skips per-database rows on pre-2016 SP2 instances' {
        BeforeAll {
            InModuleScope DbaToolbox {
                # SQL 2016 pre-SP2 (SP2 = build 13.0.5026)
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                        VersionMajor       = 13
                        BuildNumber        = 4001
                    }
                }
                Mock Invoke-DbaQuery -RemoveParameterType 'SqlInstance' -ParameterFilter { $Database -eq 'tempdb' } {
                    [PSCustomObject]@{
                        VersionStoreMB   = 5
                        UserObjectMB     = 20
                        InternalObjectMB = 2
                    }
                }
                Mock Invoke-DbaQuery -RemoveParameterType 'SqlInstance' -ParameterFilter { $Database -eq 'master' } { @() }
            }
        }

        It 'Writes a warning but does not throw' {
            { Get-VersionStoreUsage -SqlInstance 'SQL01' -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Emits no VersionStoreUsage rows and never queries the DMV' {
            $result = Get-VersionStoreUsage -SqlInstance 'SQL01' -WarningAction SilentlyContinue
            $perDb  = $result | Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.VersionStoreUsage' }
            $perDb | Should -BeNullOrEmpty
            # Only the snapshot-isolation query should hit master
            Should -Invoke Invoke-DbaQuery -ModuleName DbaToolbox -Times 1 -Exactly -ParameterFilter { $Database -eq 'master' }
        }

        It 'Still returns VersionStoreTotal' {
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
                Mock Invoke-DbaQuery -RemoveParameterType 'SqlInstance' { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-VersionStoreUsage | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
