#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-TempdbContention' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-TempdbContention -ErrorAction Stop } | Should -Throw
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
                        session_id           = 55
                        exec_context_id      = 0
                        wait_type            = 'PAGELATCH_EX'
                        wait_duration_ms     = 1500
                        resource_description = '2:1:1'
                        login_name           = 'domain\user1'
                        host_name            = 'WKSTN01'
                        program_name         = 'App'
                    }
                }
            }
        }

        It 'Has the correct PSTypeName' {
            $result = Get-TempdbContention -SqlInstance 'SQL01'
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.TempdbContention'
        }

        It 'Has all required properties' {
            $result = Get-TempdbContention -SqlInstance 'SQL01'
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'ComputerName'
            $props  | Should -Contain 'InstanceName'
            $props  | Should -Contain 'SqlInstance'
            $props  | Should -Contain 'SessionId'
            $props  | Should -Contain 'ExecContextId'
            $props  | Should -Contain 'WaitType'
            $props  | Should -Contain 'WaitDurationMs'
            $props  | Should -Contain 'ResourceDescription'
            $props  | Should -Contain 'LoginName'
            $props  | Should -Contain 'HostName'
            $props  | Should -Contain 'ProgramName'
        }
    }

    Context 'Returns empty when no waits' {
        BeforeAll {
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
        }

        It 'Returns nothing when there are no TempDB PAGELATCH waits' {
            $result = Get-TempdbContention -SqlInstance 'SQL01'
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
                Mock Invoke-DbaQuery { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-TempdbContention | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
