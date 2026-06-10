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
                Mock Invoke-DbaWhoIsActive {
                    @(
                        [PSCustomObject]@{
                            session_id          = '55'
                            elapsed_time        = '0:00:30.000'
                            blocking_session_id = ''
                            database_name       = 'AppDB'
                            login_name          = 'domain\user1'
                            host_name           = 'WKSTN01'
                            sql_text            = 'SELECT * FROM BigTable'
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
            $props  | Should -Contain 'BlockingSessionId'
            $props  | Should -Contain 'DatabaseName'
            $props  | Should -Contain 'LoginName'
            $props  | Should -Contain 'HostName'
            $props  | Should -Contain 'SqlText'
            $props  | Should -Contain 'SqlCommand'
        }

        It 'Parses elapsed_time string to TimeSpan' {
            $result = Get-LongRunningQuery -SqlInstance 'SQL01' -ThresholdSeconds 5
            $result.ElapsedTime | Should -BeOfType [timespan]
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
                Mock Invoke-DbaWhoIsActive {
                    @(
                        # 30 seconds — above threshold of 5
                        [PSCustomObject]@{
                            session_id          = '55'
                            elapsed_time        = '0:00:30.000'
                            blocking_session_id = ''
                            database_name       = 'AppDB'
                            login_name          = 'domain\user1'
                            host_name           = 'WKSTN01'
                            sql_text            = 'SELECT 1'
                            sql_command         = $null
                        },
                        # 2 seconds — below threshold of 5
                        [PSCustomObject]@{
                            session_id          = '56'
                            elapsed_time        = '0:00:02.000'
                            blocking_session_id = ''
                            database_name       = 'AppDB'
                            login_name          = 'domain\user2'
                            host_name           = 'WKSTN02'
                            sql_text            = 'SELECT 2'
                            sql_command         = $null
                        }
                    )
                }
            }
        }

        It 'Returns only sessions exceeding the threshold' {
            $result = Get-LongRunningQuery -SqlInstance 'SQL01' -ThresholdSeconds 5
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
            ($result.ElapsedTime.TotalSeconds) | Should -BeGreaterThan 5
        }

        It 'Returns nothing when all sessions are below threshold' {
            $result = Get-LongRunningQuery -SqlInstance 'SQL01' -ThresholdSeconds 60
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
                Mock Invoke-DbaWhoIsActive { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-LongRunningQuery | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
