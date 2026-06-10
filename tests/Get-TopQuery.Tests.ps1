#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-TopQuery' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-TopQuery -ErrorAction Stop } | Should -Throw
        }

        It 'Rejects an invalid SortBy value' {
            { Get-TopQuery -SqlInstance 'SQL01' -SortBy 'InvalidMetric' } | Should -Throw
        }

        It 'Accepts all valid SortBy values' {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Invoke-DbaQuery { @() }
            }
            foreach ($sortBy in 'CPU', 'LogicalReads', 'LogicalWrites') {
                { Get-TopQuery -SqlInstance 'SQL01' -SortBy $sortBy } | Should -Not -Throw
            }
        }
    }

    Context 'Output object shape' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Invoke-DbaQuery {
                    [PSCustomObject]@{
                        DatabaseName       = 'AppDB'
                        ExecutionCount     = 1000
                        TotalCpuSec        = 250.5
                        AvgCpuSec          = 0.2505
                        TotalLogicalReads  = 500000
                        AvgLogicalReads    = 500
                        TotalLogicalWrites = 1000
                        AvgLogicalWrites   = 1
                        AvgElapsedSec      = 0.350
                        QueryText          = 'SELECT col FROM dbo.Table'
                    }
                }
            }
        }

        It 'Has the correct PSTypeName' {
            $result = Get-TopQuery -SqlInstance 'SQL01'
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.TopQuery'
        }

        It 'Has all required properties' {
            $result = Get-TopQuery -SqlInstance 'SQL01'
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'ComputerName'
            $props  | Should -Contain 'InstanceName'
            $props  | Should -Contain 'SqlInstance'
            $props  | Should -Contain 'DatabaseName'
            $props  | Should -Contain 'ExecutionCount'
            $props  | Should -Contain 'TotalCpuSec'
            $props  | Should -Contain 'AvgCpuSec'
            $props  | Should -Contain 'TotalLogicalReads'
            $props  | Should -Contain 'AvgLogicalReads'
            $props  | Should -Contain 'TotalLogicalWrites'
            $props  | Should -Contain 'AvgLogicalWrites'
            $props  | Should -Contain 'AvgElapsedSec'
            $props  | Should -Contain 'QueryText'
        }

        It 'Always populates all three metric sets' {
            $result = Get-TopQuery -SqlInstance 'SQL01'
            $result.TotalCpuSec       | Should -Not -BeNullOrEmpty
            $result.TotalLogicalReads | Should -Not -BeNullOrEmpty
            $result.TotalLogicalWrites | Should -Not -BeNullOrEmpty
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
            'SQL01', 'SQL02' | Get-TopQuery | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
