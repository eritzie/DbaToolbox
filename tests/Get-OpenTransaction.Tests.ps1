#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-OpenTransaction' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-OpenTransaction -ErrorAction Stop } | Should -Throw
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
                # Mirrors real sp_WhoIsActive -GetTransactionInfo output: adds
                # tran_start_time, tran_log_writes, implicit_tran. There is NO
                # tran_log_used_percent column. open_tran_count arrives as a string.
                Mock Invoke-DbaWhoIsActive -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            session_id          = '75'
                            status              = 'sleeping'
                            blocking_session_id = ''
                            open_tran_count     = '1'
                            tran_start_time     = [datetime]'2026-07-06 10:00:00'
                            tran_log_writes     = 'AppDB: 42 (2 kB)'
                            implicit_tran       = 'OFF'
                            database_name       = 'AppDB'
                            login_name          = 'domain\user1'
                            host_name           = 'WKSTN01'
                            sql_text            = 'BEGIN TRAN'
                        }
                    )
                }
            }
        }

        It 'Has the correct PSTypeName' {
            $result = Get-OpenTransaction -SqlInstance 'SQL01'
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.OpenTransaction'
        }

        It 'Has all required properties' {
            $result = Get-OpenTransaction -SqlInstance 'SQL01'
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'ComputerName'
            $props  | Should -Contain 'InstanceName'
            $props  | Should -Contain 'SqlInstance'
            $props  | Should -Contain 'SessionId'
            $props  | Should -Contain 'Status'
            $props  | Should -Contain 'BlockingSessionId'
            $props  | Should -Contain 'OpenTranCount'
            $props  | Should -Contain 'TranStartTime'
            $props  | Should -Contain 'TranLogWrites'
            $props  | Should -Contain 'ImplicitTran'
            $props  | Should -Contain 'DatabaseName'
            $props  | Should -Contain 'LoginName'
            $props  | Should -Contain 'HostName'
            $props  | Should -Contain 'SqlText'
        }

        It 'Casts OpenTranCount to int' {
            $result = Get-OpenTransaction -SqlInstance 'SQL01'
            $result.OpenTranCount | Should -BeOfType [int]
        }
    }

    Context 'Transaction filter' {
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
                        # Has open transaction — should be included
                        [PSCustomObject]@{
                            session_id          = '80'
                            status              = 'sleeping'
                            blocking_session_id = ''
                            open_tran_count     = '2'
                            tran_start_time     = [datetime]'2026-07-06 09:00:00'
                            tran_log_writes     = 'AppDB: 10 (1 kB)'
                            implicit_tran       = 'OFF'
                            database_name       = 'AppDB'
                            login_name          = 'domain\user1'
                            host_name           = 'WKSTN01'
                            sql_text            = 'BEGIN TRAN'
                        },
                        # No open transaction — should be excluded
                        [PSCustomObject]@{
                            session_id          = '81'
                            status              = 'sleeping'
                            blocking_session_id = ''
                            open_tran_count     = '0'
                            tran_start_time     = [DBNull]::Value
                            tran_log_writes     = $null
                            implicit_tran       = 'OFF'
                            database_name       = 'AppDB'
                            login_name          = 'domain\user2'
                            host_name           = 'WKSTN02'
                            sql_text            = $null
                        }
                    )
                }
            }
        }

        It 'Returns only sessions with open_tran_count greater than zero' {
            $result = Get-OpenTransaction -SqlInstance 'SQL01'
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
            $result.LoginName | Should -Be 'domain\user1'
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
            'SQL01', 'SQL02' | Get-OpenTransaction | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
