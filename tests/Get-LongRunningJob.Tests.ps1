#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-LongRunningJob' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-LongRunningJob -ErrorAction Stop } | Should -Throw
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
                # Running job whose LastRunDate is 20 minutes ago
                Mock Get-DbaRunningJob {
                    @(
                        [PSCustomObject]@{
                            Name        = 'DBAOps - Nightly Backup'
                            LastRunDate = (Get-Date).AddMinutes(-20)
                        }
                    )
                }
                # History: average duration 5 minutes — so 20min is 4x average (above 2x multiplier)
                Mock Get-DbaAgentJobHistory {
                    @(
                        [PSCustomObject]@{
                            Status   = 'Succeeded'
                            Job      = 'DBAOps - Nightly Backup'
                            Duration = [timespan]::FromMinutes(5)
                        },
                        [PSCustomObject]@{
                            Status   = 'Succeeded'
                            Job      = 'DBAOps - Nightly Backup'
                            Duration = [timespan]::FromMinutes(5)
                        }
                    )
                }
            }
        }

        It 'Has the correct PSTypeName' {
            $result = Get-LongRunningJob -SqlInstance 'SQL01'
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.LongRunningJob'
        }

        It 'Has all required properties' {
            $result = Get-LongRunningJob -SqlInstance 'SQL01'
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'ComputerName'
            $props  | Should -Contain 'InstanceName'
            $props  | Should -Contain 'SqlInstance'
            $props  | Should -Contain 'JobName'
            $props  | Should -Contain 'StartDate'
            $props  | Should -Contain 'CurrentDuration'
            $props  | Should -Contain 'AvgDuration'
            $props  | Should -Contain 'Multiplier'
        }

        It 'Returns CurrentDuration as TimeSpan' {
            $result = Get-LongRunningJob -SqlInstance 'SQL01'
            $result.CurrentDuration | Should -BeOfType [timespan]
        }
    }

    Context 'Multiplier filter' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                # Running job 20 minutes (average is 5 minutes => 4x)
                Mock Get-DbaRunningJob {
                    @(
                        [PSCustomObject]@{
                            Name        = 'DBAOps - Nightly Backup'
                            LastRunDate = (Get-Date).AddMinutes(-20)
                        }
                    )
                }
                Mock Get-DbaAgentJobHistory {
                    @(
                        [PSCustomObject]@{
                            Status   = 'Succeeded'
                            Job      = 'DBAOps - Nightly Backup'
                            Duration = [timespan]::FromMinutes(5)
                        }
                    )
                }
            }
        }

        It 'Returns the job when current duration exceeds multiplier threshold' {
            $result = Get-LongRunningJob -SqlInstance 'SQL01' -Multiplier 2.0
            $result | Should -Not -BeNullOrEmpty
            $result.Multiplier | Should -BeGreaterThan 2.0
        }

        It 'Returns nothing when multiplier threshold is set high enough' {
            $result = Get-LongRunningJob -SqlInstance 'SQL01' -Multiplier 10.0
            $result | Should -BeNullOrEmpty
        }

        It 'Excludes jobs in ExcludeJob list' {
            $result = Get-LongRunningJob -SqlInstance 'SQL01' -ExcludeJob 'DBAOps - Nightly Backup'
            $result | Should -BeNullOrEmpty
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
                Mock Get-DbaRunningJob { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-LongRunningJob | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
