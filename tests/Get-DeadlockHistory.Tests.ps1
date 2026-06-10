#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-DeadlockHistory' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-DeadlockHistory -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Default output (DeadlockEvent)' {
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
                        DeadlockId    = 42
                        EventTime     = [datetime]'2026-06-09 10:00:00'
                        DatabaseName  = 'AppDB'
                        VictimProcess = 'process55'
                        CapturedAt    = [datetime]'2026-06-09 10:05:00'
                    }
                }
            }
        }

        It 'Returns DbaToolbox.DeadlockEvent by default' {
            $result = Get-DeadlockHistory -SqlInstance 'SQL01'
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.DeadlockEvent'
        }

        It 'Has required DeadlockEvent properties' {
            $result = Get-DeadlockHistory -SqlInstance 'SQL01'
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'DeadlockId'
            $props  | Should -Contain 'EventTime'
            $props  | Should -Contain 'DatabaseName'
            $props  | Should -Contain 'VictimProcess'
            $props  | Should -Contain 'CapturedAt'
        }
    }

    Context '-Summary output (DeadlockSummary)' {
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
                        DatabaseName  = 'AppDB'
                        DeadlockCount = 15
                        FirstSeen     = [datetime]'2026-06-01'
                        LastSeen      = [datetime]'2026-06-09'
                    }
                }
            }
        }

        It 'Returns DbaToolbox.DeadlockSummary with -Summary' {
            $result = Get-DeadlockHistory -SqlInstance 'SQL01' -Summary
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.DeadlockSummary'
        }

        It 'Has required DeadlockSummary properties' {
            $result = Get-DeadlockHistory -SqlInstance 'SQL01' -Summary
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'DatabaseName'
            $props  | Should -Contain 'DeadlockCount'
            $props  | Should -Contain 'FirstSeen'
            $props  | Should -Contain 'LastSeen'
        }
    }

    Context '-Id output (DeadlockGraph)' {
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
                        DeadlockId    = 42
                        EventTime     = [datetime]'2026-06-09 10:00:00'
                        DatabaseName  = 'AppDB'
                        VictimProcess = 'process55'
                        DeadlockGraph = '<deadlock><victim-list/></deadlock>'
                    }
                }
            }
        }

        It 'Returns DbaToolbox.DeadlockGraph with -Id' {
            $result = Get-DeadlockHistory -SqlInstance 'SQL01' -Id 42
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.DeadlockGraph'
        }

        It 'Includes DeadlockGraph property' {
            $result = Get-DeadlockHistory -SqlInstance 'SQL01' -Id 42
            $result.PSObject.Properties.Name | Should -Contain 'DeadlockGraph'
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
            'SQL01', 'SQL02' | Get-DeadlockHistory | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
