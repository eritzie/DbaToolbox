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
                # Mirrors real sp_WhoIsActive output: wait_info is a combined string,
                # numerics arrive as strings (@format_output = 1), start_time is datetime.
                # There is NO wait_type, wait_time, or elapsed_time column.
                Mock Invoke-DbaWhoIsActive -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            session_id            = '61'
                            blocking_session_id   = ''
                            blocked_session_count = '1'
                            wait_info             = '(32440753ms)ASYNC_IO_COMPLETION'
                            start_time            = (Get-Date).AddMinutes(-540)
                            collection_time       = Get-Date
                            database_name         = 'AppDB'
                            login_name            = 'domain\user1'
                            sql_text              = 'SELECT 1'
                            host_name             = 'WKSTN01'
                            program_name          = 'SSMS'
                            status                = 'suspended'
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
            $props  | Should -Contain 'WaitInfo'
            $props  | Should -Contain 'StartTime'
            $props  | Should -Contain 'DatabaseName'
            $props  | Should -Contain 'LoginName'
            $props  | Should -Contain 'SqlText'
        }

        It 'Casts SessionId to int' {
            $result = Get-BlockingSession -SqlInstance 'SQL01'
            $result.SessionId | Should -BeOfType [int]
        }

        It 'Passes wait_info through unaltered' {
            $result = Get-BlockingSession -SqlInstance 'SQL01'
            $result.WaitInfo | Should -Be '(32440753ms)ASYNC_IO_COMPLETION'
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
                Mock Invoke-DbaWhoIsActive -RemoveParameterType 'SqlInstance' {
                    @(
                        # Head blocker — blocked_session_count > 0
                        [PSCustomObject]@{
                            session_id            = '55'
                            blocking_session_id   = ''
                            blocked_session_count = '2'
                            wait_info             = $null
                            start_time            = (Get-Date).AddMinutes(-10)
                            collection_time       = Get-Date
                            database_name         = 'AppDB'
                            login_name            = 'domain\blocker'
                            sql_text              = 'BEGIN TRAN'
                            host_name             = 'WKSTN01'
                            program_name          = 'SSMS'
                            status                = 'sleeping'
                            locks                 = $null
                            sql_command           = $null
                        },
                        # Non-blocking session — should be excluded
                        [PSCustomObject]@{
                            session_id            = '60'
                            blocking_session_id   = ''
                            blocked_session_count = '0'
                            wait_info             = $null
                            start_time            = (Get-Date).AddSeconds(-5)
                            collection_time       = Get-Date
                            database_name         = 'AppDB'
                            login_name            = 'domain\user'
                            sql_text              = 'SELECT 1'
                            host_name             = 'WKSTN02'
                            program_name          = 'App'
                            status                = 'running'
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

    Context '-Detailed switch' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Invoke-DbaWhoIsActive -RemoveParameterType 'SqlInstance' { @() }
            }
        }

        It 'Requests locks, task info, and outer command from sp_WhoIsActive' {
            Get-BlockingSession -SqlInstance 'SQL01' -Detailed | Out-Null
            Should -Invoke Invoke-DbaWhoIsActive -ModuleName DbaToolbox -Times 1 -Exactly -ParameterFilter {
                $GetLocks -eq $true -and $GetTaskInfo -eq 2 -and $GetOuterCommand -eq $true
            }
        }

        It 'Does not request outer command when -Detailed is omitted' {
            Get-BlockingSession -SqlInstance 'SQL01' | Out-Null
            Should -Invoke Invoke-DbaWhoIsActive -ModuleName DbaToolbox -Times 1 -Exactly -ParameterFilter {
                -not $PSBoundParameters.ContainsKey('GetOuterCommand')
            }
        }
    }

    Context 'Connection resilience' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    if ("$SqlInstance" -like '*BAD*') { throw 'connection refused' }
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Invoke-DbaWhoIsActive -RemoveParameterType 'SqlInstance' { @() }
            }
        }

        It 'Warns and continues to the next instance when one connection fails' {
            Get-BlockingSession -SqlInstance 'SQL-BAD', 'SQL01' -WarningAction SilentlyContinue -WarningVariable w | Out-Null
            $w | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-DbaWhoIsActive -ModuleName DbaToolbox -Times 1 -Exactly
        }

        It 'Throws on connection failure when -EnableException is set' {
            { Get-BlockingSession -SqlInstance 'SQL-BAD' -EnableException } | Should -Throw
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
                Mock Invoke-DbaWhoIsActive -RemoveParameterType 'SqlInstance' { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-BlockingSession | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
