#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-ConnectionSummary' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-ConnectionSummary -ErrorAction Stop } | Should -Throw
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
                Mock Get-DbaProcess -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            Database = 'AppDB'
                            Login    = 'domain\user1'
                            Host     = 'WKSTN01'
                            Program  = 'SSMS'
                            Status   = 'sleeping'
                            Command  = 'AWAITING COMMAND'
                        },
                        [PSCustomObject]@{
                            Database = 'AppDB'
                            Login    = 'domain\user1'
                            Host     = 'WKSTN01'
                            Program  = 'SSMS'
                            Status   = 'sleeping'
                            Command  = 'AWAITING COMMAND'
                        }
                    )
                }
            }
        }

        It 'Has the correct PSTypeName' {
            $result = Get-ConnectionSummary -SqlInstance 'SQL01'
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.ConnectionSummary'
        }

        It 'Has all required properties' {
            $result = Get-ConnectionSummary -SqlInstance 'SQL01'
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'ComputerName'
            $props  | Should -Contain 'InstanceName'
            $props  | Should -Contain 'SqlInstance'
            $props  | Should -Contain 'DatabaseName'
            $props  | Should -Contain 'LoginName'
            $props  | Should -Contain 'Host'
            $props  | Should -Contain 'Program'
            $props  | Should -Contain 'Status'
            $props  | Should -Contain 'Command'
            $props  | Should -Contain 'ConnectionCount'
        }

        It 'Groups sessions and returns correct ConnectionCount' {
            $result = Get-ConnectionSummary -SqlInstance 'SQL01'
            $result | Should -Not -BeNullOrEmpty
            $result.ConnectionCount | Should -Be 2
        }
    }

    Context 'Filtering' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Get-DbaProcess -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            Database = 'AppDB'
                            Login    = 'domain\user1'
                            Host     = 'WKSTN01'
                            Program  = 'SSMS'
                            Status   = 'sleeping'
                            Command  = 'AWAITING COMMAND'
                        },
                        [PSCustomObject]@{
                            Database = 'OtherDB'
                            Login    = 'domain\user2'
                            Host     = 'WKSTN02'
                            Program  = 'App'
                            Status   = 'running'
                            Command  = 'SELECT'
                        }
                    )
                }
            }
        }

        It 'Filters by Database' {
            $result = Get-ConnectionSummary -SqlInstance 'SQL01' -Database 'AppDB'
            $result | Should -Not -BeNullOrEmpty
            $result.DatabaseName | Should -Be 'AppDB'
        }

        It 'Filters by Login' {
            $result = Get-ConnectionSummary -SqlInstance 'SQL01' -Login 'domain\user2'
            $result | Should -Not -BeNullOrEmpty
            $result.LoginName | Should -Be 'domain\user2'
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
                Mock Get-DbaProcess -RemoveParameterType 'SqlInstance' { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-ConnectionSummary | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
