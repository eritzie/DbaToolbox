#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-LongRunningQuery' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-LongRunningQuery -ErrorAction Stop } | Should -Throw
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
                # Mirrors real sp_WhoIsActive output: there is NO elapsed_time column —
                # elapsed is computed from the start_time/collection_time datetimes.
                Mock Invoke-DbaWhoIsActive -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            session_id          = '55'
                            start_time          = (Get-Date).AddSeconds(-30)
                            collection_time     = Get-Date
                            blocking_session_id = ''
                            status              = 'running'
                            database_name       = 'AppDB'
                            login_name          = 'domain\user1'
                            host_name           = 'WKSTN01'
                            program_name        = 'App'
                            sql_text            = 'SELECT 1 FROM dbo.BigTable'
                            sql_command         = $null
                        }
                    )
                }
            }
        }

        It 'Has the correct PSTypeName' {
            $result = Get-LongRunningQuery -SqlInstance 'SQL01' -ThresholdSeconds 5
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.LongRunningQuery'
        }

        It 'Has all required properties' {
            $result = Get-LongRunningQuery -SqlInstance 'SQL01' -ThresholdSeconds 5
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'ComputerName'
            $props  | Should -Contain 'InstanceName'
            $props  | Should -Contain 'SqlInstance'
            $props  | Should -Contain 'SessionId'
            $props  | Should -Contain 'ElapsedTime'
            $props  | Should -Contain 'Status'
            $props  | Should -Contain 'BlockingSessionId'
            $props  | Should -Contain 'DatabaseName'
            $props  | Should -Contain 'LoginName'
            $props  | Should -Contain 'HostName'
            $props  | Should -Contain 'ProgramName'
            $props  | Should -Contain 'SqlText'
            $props  | Should -Contain 'SqlCommand'
        }

        It 'Computes ElapsedTime as a TimeSpan from start_time/collection_time' {
            $result = Get-LongRunningQuery -SqlInstance 'SQL01' -ThresholdSeconds 5
            $result.ElapsedTime | Should -BeOfType [timespan]
            $result.ElapsedTime.TotalSeconds | Should -BeGreaterThan 25
        }
    }

    Context 'ThresholdSeconds filter' {
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
                        # 30 seconds — above threshold of 5
                        [PSCustomObject]@{
                            session_id          = '55'
                            start_time          = (Get-Date).AddSeconds(-30)
                            collection_time     = Get-Date
                            blocking_session_id = ''
                            status              = 'running'
                            database_name       = 'AppDB'
                            login_name          = 'domain\user1'
                            host_name           = 'WKSTN01'
                            program_name        = 'App'
                            sql_text            = 'SELECT 1'
                            sql_command         = $null
                        },
                        # 2 seconds — below threshold of 5
                        [PSCustomObject]@{
                            session_id          = '56'
                            start_time          = (Get-Date).AddSeconds(-2)
                            collection_time     = Get-Date
                            blocking_session_id = ''
                            status              = 'running'
                            database_name       = 'AppDB'
                            login_name          = 'domain\user2'
                            host_name           = 'WKSTN02'
                            program_name        = 'App'
                            sql_text            = 'SELECT 2'
                            sql_command         = $null
                        },
                        # Multi-day runtime — must not be silently dropped
                        [PSCustomObject]@{
                            session_id          = '57'
                            start_time          = (Get-Date).AddDays(-2)
                            collection_time     = Get-Date
                            blocking_session_id = ''
                            status              = 'suspended'
                            database_name       = 'AppDB'
                            login_name          = 'domain\user3'
                            host_name           = 'WKSTN03'
                            program_name        = 'App'
                            sql_text            = 'SELECT 3'
                            sql_command         = $null
                        }
                    )
                }
            }
        }

        It 'Returns only sessions exceeding the threshold' {
            $result = @(Get-LongRunningQuery -SqlInstance 'SQL01' -ThresholdSeconds 5)
            $result.Count | Should -Be 2
            $result.SessionId | Should -Not -Contain 56
        }

        It 'Handles multi-day runtimes' {
            $result = Get-LongRunningQuery -SqlInstance 'SQL01' -ThresholdSeconds 5 |
                Where-Object SessionId -eq 57
            $result | Should -Not -BeNullOrEmpty
            $result.ElapsedTime.TotalDays | Should -BeGreaterThan 1.9
        }

        It 'Returns nothing when all sessions are below threshold' {
            $result = Get-LongRunningQuery -SqlInstance 'SQL01' -ThresholdSeconds 999999
            $result | Should -BeNullOrEmpty
        }

        It 'Skips sessions without a valid start_time' {
            InModuleScope DbaToolbox {
                Mock Invoke-DbaWhoIsActive -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            session_id          = '58'
                            start_time          = [DBNull]::Value
                            collection_time     = Get-Date
                            blocking_session_id = ''
                            status              = 'running'
                            database_name       = 'AppDB'
                            login_name          = 'domain\user4'
                            host_name           = 'WKSTN04'
                            program_name        = 'App'
                            sql_text            = 'SELECT 4'
                            sql_command         = $null
                        }
                    )
                }
            }
            $result = Get-LongRunningQuery -SqlInstance 'SQL01' -ThresholdSeconds 1
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
                Mock Invoke-DbaWhoIsActive -RemoveParameterType 'SqlInstance' { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-LongRunningQuery | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
