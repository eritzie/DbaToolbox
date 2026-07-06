#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-FailedLogin' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-FailedLogin -ErrorAction Stop } | Should -Throw
        }

        It 'Rejects negative log numbers' {
            { Get-FailedLogin -SqlInstance 'SQL01' -LogNumber -1 -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Output object shape and parsing' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                # Mirrors real xp_readerrorlog output columns: LogDate, ProcessInfo, Text
                Mock Invoke-DbaQuery -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            LogDate     = [datetime]'2026-07-06 08:00:00'
                            ProcessInfo = 'Logon'
                            Text        = "Login failed for user 'svc_app'. Reason: Password did not match that for the login provided. [CLIENT: 10.0.0.5]"
                        },
                        [PSCustomObject]@{
                            LogDate     = [datetime]'2026-07-06 09:30:00'
                            ProcessInfo = 'Logon'
                            Text        = "Login failed for user 'svc_app'. Reason: Password did not match that for the login provided. [CLIENT: 10.0.0.5]"
                        },
                        [PSCustomObject]@{
                            LogDate     = [datetime]'2026-07-06 10:00:00'
                            ProcessInfo = 'Logon'
                            Text        = "Login failed for user 'DOMAIN\jdoe'. Reason: Failed to open the explicitly specified database 'GoneDB'. [CLIENT: 10.0.0.9]"
                        }
                    )
                }
            }
        }

        It 'Has the correct PSTypeName' {
            $result = Get-FailedLogin -SqlInstance 'SQL01'
            $result[0].PSObject.TypeNames[0] | Should -Be 'DbaToolbox.FailedLogin'
        }

        It 'Has all required properties' {
            $result = Get-FailedLogin -SqlInstance 'SQL01'
            $props  = $result[0].PSObject.Properties.Name
            $props  | Should -Contain 'ComputerName'
            $props  | Should -Contain 'InstanceName'
            $props  | Should -Contain 'SqlInstance'
            $props  | Should -Contain 'Login'
            $props  | Should -Contain 'Reason'
            $props  | Should -Contain 'ClientAddress'
            $props  | Should -Contain 'FailureCount'
            $props  | Should -Contain 'FirstSeen'
            $props  | Should -Contain 'LastSeen'
        }

        It 'Groups repeated failures and counts them' {
            $result = @(Get-FailedLogin -SqlInstance 'SQL01')
            $result.Count | Should -Be 2
            $svcApp = $result | Where-Object Login -eq 'svc_app'
            $svcApp.FailureCount | Should -Be 2
            $svcApp.FirstSeen | Should -Be ([datetime]'2026-07-06 08:00:00')
            $svcApp.LastSeen  | Should -Be ([datetime]'2026-07-06 09:30:00')
        }

        It 'Parses login, reason, and client address from the message text' {
            $result = Get-FailedLogin -SqlInstance 'SQL01' | Where-Object Login -eq 'DOMAIN\jdoe'
            $result.Reason        | Should -Be "Failed to open the explicitly specified database 'GoneDB'."
            $result.ClientAddress | Should -Be '10.0.0.9'
        }

        It 'Filters server-side via xp_readerrorlog parameters' {
            Get-FailedLogin -SqlInstance 'SQL01' -HoursBack 48 | Out-Null
            Should -Invoke Invoke-DbaQuery -ModuleName DbaToolbox -Times 1 -Exactly -ParameterFilter {
                $Query -match 'xp_readerrorlog' -and
                $SqlParameter.Search1 -eq 'Login failed' -and
                $SqlParameter.After -gt (Get-Date).AddHours(-49) -and
                $SqlParameter.After -lt (Get-Date).AddHours(-47)
            }
        }

        It 'Reads one log per requested LogNumber' {
            Get-FailedLogin -SqlInstance 'SQL01' -LogNumber 0, 1 | Out-Null
            Should -Invoke Invoke-DbaQuery -ModuleName DbaToolbox -Times 2 -Exactly -ParameterFilter {
                $Query -match 'xp_readerrorlog'
            }
        }
    }

    Context 'No failed logins' {
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

        It 'Returns nothing when the error log has no failed logins' {
            $result = Get-FailedLogin -SqlInstance 'SQL01'
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
            'SQL01', 'SQL02' | Get-FailedLogin | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
