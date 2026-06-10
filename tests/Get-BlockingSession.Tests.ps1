#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-BlockingSession' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-BlockingSession -ErrorAction Stop } | Should -Throw
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
                Mock Invoke-DbaWhoIsActive {
                    @(
                        [PSCustomObject]@{
                            session_id            = '61'
                            blocking_session_id   = ''
                            blocked_session_count = '1'
                            wait_type             = 'ASYNC_IO_COMPLETION'
                            wait_time             = '32440753ms'
                            database_name         = 'AppDB'
                            login_name            = 'domain\user1'
                            sql_text              = 'SELECT 1'
                            host_name             = 'WKSTN01'
                            locks                 = $null
                            sql_command           = $null
                        }
                    )
                }
            }
        }

        It 'Has the correct PSTypeName' {
            $result = Get-BlockingSession -SqlInstance 'SQL01'
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.BlockingSession'
        }

        It 'Has all required properties' {
            $result = Get-BlockingSession -SqlInstance 'SQL01'
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'ComputerName'
            $props  | Should -Contain 'InstanceName'
            $props  | Should -Contain 'SqlInstance'
            $props  | Should -Contain 'SessionId'
            $props  | Should -Contain 'BlockingSessionId'
            $props  | Should -Contain 'BlockedSessionCount'
            $props  | Should -Contain 'WaitType'
            $props  | Should -Contain 'DatabaseName'
            $props  | Should -Contain 'LoginName'
            $props  | Should -Contain 'SqlText'
        }

        It 'Casts SessionId to int' {
            $result = Get-BlockingSession -SqlInstance 'SQL01'
            $result.SessionId | Should -BeOfType [int]
        }
    }

    Context 'Blocking filter' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Invoke-DbaWhoIsActive {
                    @(
                        # Head blocker — blocked_session_count > 0
                        [PSCustomObject]@{
                            session_id            = '55'
                            blocking_session_id   = ''
                            blocked_session_count = '2'
                            wait_type             = $null
                            wait_time             = $null
                            database_name         = 'AppDB'
                            login_name            = 'domain\blocker'
                            sql_text              = 'BEGIN TRAN'
                            host_name             = 'WKSTN01'
                            locks                 = $null
                            sql_command           = $null
                        },
                        # Non-blocking session — should be excluded
                        [PSCustomObject]@{
                            session_id            = '60'
                            blocking_session_id   = ''
                            blocked_session_count = '0'
                            wait_type             = $null
                            wait_time             = $null
                            database_name         = 'AppDB'
                            login_name            = 'domain\user'
                            sql_text              = 'SELECT 1'
                            host_name             = 'WKSTN02'
                            locks                 = $null
                            sql_command           = $null
                        }
                    )
                }
            }
        }

        It 'Returns only sessions with blocking or being blocked' {
            $result = Get-BlockingSession -SqlInstance 'SQL01'
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
            $result.LoginName | Should -Be 'domain\blocker'
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
                Mock Invoke-DbaWhoIsActive { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-BlockingSession | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
