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
                Mock Invoke-DbaQuery -RemoveParameterType 'SqlInstance' {
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
            $props  | Should -Contain 'PageType'
            $props  | Should -Contain 'LoginName'
            $props  | Should -Contain 'HostName'
            $props  | Should -Contain 'ProgramName'
        }
    }

    Context 'PageType classification' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Invoke-DbaQuery -RemoveParameterType 'SqlInstance' {
                    foreach ($rd in '2:1:1', '2:1:8088', '2:3:2', '2:1:511232', '2:2:3', '2:1:511233', '2:1:500') {
                        [PSCustomObject]@{
                            session_id           = 55
                            exec_context_id      = 0
                            wait_type            = 'PAGELATCH_UP'
                            wait_duration_ms     = 100
                            resource_description = $rd
                            login_name           = 'domain\user1'
                            host_name            = 'WKSTN01'
                            program_name         = 'App'
                        }
                    }
                }
            }
        }

        It 'Classifies PFS, GAM, SGAM, and Other pages' {
            $result = @(Get-TempdbContention -SqlInstance 'SQL01')
            ($result | Where-Object ResourceDescription -eq '2:1:1').PageType      | Should -Be 'PFS'
            ($result | Where-Object ResourceDescription -eq '2:1:8088').PageType   | Should -Be 'PFS'
            ($result | Where-Object ResourceDescription -eq '2:3:2').PageType      | Should -Be 'GAM'
            ($result | Where-Object ResourceDescription -eq '2:1:511232').PageType | Should -Be 'GAM'
            ($result | Where-Object ResourceDescription -eq '2:2:3').PageType      | Should -Be 'SGAM'
            ($result | Where-Object ResourceDescription -eq '2:1:511233').PageType | Should -Be 'SGAM'
            ($result | Where-Object ResourceDescription -eq '2:1:500').PageType    | Should -Be 'Other'
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
                Mock Invoke-DbaQuery -RemoveParameterType 'SqlInstance' { @() }
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
                Mock Invoke-DbaQuery -RemoveParameterType 'SqlInstance' { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-TempdbContention | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
