#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-WaitStatistic' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-WaitStatistic -ErrorAction Stop } | Should -Throw
        }

        It 'Rejects SampleSeconds outside 1-3600' {
            { Get-WaitStatistic -SqlInstance 'SQL01' -SampleSeconds 0 -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Cumulative mode output' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Get-DbaWaitStatistic -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            WaitType           = 'CXPACKET'
                            Category           = 'Parallelism'
                            WaitSeconds        = 489.96
                            ResourceSeconds    = 400.12
                            SignalSeconds      = 89.84
                            WaitCount          = 100000
                            Percentage         = 40.78
                            AverageWaitSeconds = 0.005
                            URL                = 'https://www.sqlskills.com/help/waits/CXPACKET'
                        }
                    )
                }
            }
        }

        It 'Has the correct PSTypeName' {
            $result = Get-WaitStatistic -SqlInstance 'SQL01'
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.WaitStatistic'
        }

        It 'Has all required properties' {
            $result = Get-WaitStatistic -SqlInstance 'SQL01'
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'ComputerName'
            $props  | Should -Contain 'InstanceName'
            $props  | Should -Contain 'SqlInstance'
            $props  | Should -Contain 'WaitType'
            $props  | Should -Contain 'Category'
            $props  | Should -Contain 'WaitSeconds'
            $props  | Should -Contain 'ResourceSeconds'
            $props  | Should -Contain 'SignalSeconds'
            $props  | Should -Contain 'WaitCount'
            $props  | Should -Contain 'Percentage'
            $props  | Should -Contain 'AverageWaitSeconds'
        }

        It 'Passes Threshold through to Get-DbaWaitStatistic' {
            Get-WaitStatistic -SqlInstance 'SQL01' -Threshold 80 | Out-Null
            Should -Invoke Get-DbaWaitStatistic -ModuleName DbaToolbox -Times 1 -Exactly -ParameterFilter {
                $Threshold -eq 80
            }
        }
    }

    Context 'Sample mode output' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Start-Sleep { }
                $script:waitSnapshot = 0
                Mock Get-DbaWaitStatistic -RemoveParameterType 'SqlInstance' {
                    $script:waitSnapshot++
                    if ($script:waitSnapshot -eq 1) {
                        @(
                            [PSCustomObject]@{ WaitType = 'PAGEIOLATCH_SH'; Category = 'Buffer IO'; WaitSeconds = 100.0; SignalSeconds = 1.0; WaitCount = 1000 },
                            [PSCustomObject]@{ WaitType = 'SOS_SCHEDULER_YIELD'; Category = 'CPU'; WaitSeconds = 50.0; SignalSeconds = 50.0; WaitCount = 500 }
                        )
                    } else {
                        @(
                            # +30s during the sample
                            [PSCustomObject]@{ WaitType = 'PAGEIOLATCH_SH'; Category = 'Buffer IO'; WaitSeconds = 130.0; SignalSeconds = 1.5; WaitCount = 1300 },
                            # unchanged — should be excluded
                            [PSCustomObject]@{ WaitType = 'SOS_SCHEDULER_YIELD'; Category = 'CPU'; WaitSeconds = 50.0; SignalSeconds = 50.0; WaitCount = 500 },
                            # new wait during the sample — baseline 0
                            [PSCustomObject]@{ WaitType = 'LCK_M_X'; Category = 'Lock'; WaitSeconds = 10.0; SignalSeconds = 0.1; WaitCount = 5 }
                        )
                    }
                }
            }
        }

        BeforeEach {
            InModuleScope DbaToolbox { $script:waitSnapshot = 0 }
        }

        It 'Emits WaitSample rows with deltas only' {
            $result = @(Get-WaitStatistic -SqlInstance 'SQL01' -SampleSeconds 10)
            $result.Count | Should -Be 2
            $result[0].PSObject.TypeNames[0] | Should -Be 'DbaToolbox.WaitSample'
            $result.WaitType | Should -Not -Contain 'SOS_SCHEDULER_YIELD'
        }

        It 'Computes correct deltas and sorts descending' {
            $result = @(Get-WaitStatistic -SqlInstance 'SQL01' -SampleSeconds 10)
            $result[0].WaitType | Should -Be 'PAGEIOLATCH_SH'
            $result[0].WaitSecondsDelta | Should -Be 30
            $result[0].WaitCountDelta | Should -Be 300
            $result[1].WaitType | Should -Be 'LCK_M_X'
            $result[1].WaitSecondsDelta | Should -Be 10
        }

        It 'Computes percentage of the delta total' {
            $result = @(Get-WaitStatistic -SqlInstance 'SQL01' -SampleSeconds 10)
            $result[0].Percentage | Should -Be 75
            $result[1].Percentage | Should -Be 25
        }

        It 'Takes exactly two snapshots' {
            Get-WaitStatistic -SqlInstance 'SQL01' -SampleSeconds 10 | Out-Null
            Should -Invoke Get-DbaWaitStatistic -ModuleName DbaToolbox -Times 2 -Exactly
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
                Mock Get-DbaWaitStatistic -RemoveParameterType 'SqlInstance' { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-WaitStatistic | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
