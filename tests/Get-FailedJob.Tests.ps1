#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-FailedJob' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-FailedJob -ErrorAction Stop } | Should -Throw
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
                Mock Get-DbaAgentJobHistory -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            Status   = 'Failed'
                            Job      = 'DBAOps - Nightly Backup'
                            RunDate  = (Get-Date).AddHours(-2)
                            Duration = [timespan]::FromSeconds(45)
                            Message  = 'Step failed.'
                        }
                    )
                }
            }
        }

        It 'Has the correct PSTypeName' {
            $result = Get-FailedJob -SqlInstance 'SQL01'
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.FailedJob'
        }

        It 'Has all required properties' {
            $result = Get-FailedJob -SqlInstance 'SQL01'
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'ComputerName'
            $props  | Should -Contain 'InstanceName'
            $props  | Should -Contain 'SqlInstance'
            $props  | Should -Contain 'JobName'
            $props  | Should -Contain 'RunDate'
            $props  | Should -Contain 'Duration'
            $props  | Should -Contain 'Message'
        }

        It 'Maps Job property to JobName' {
            $result = Get-FailedJob -SqlInstance 'SQL01'
            $result.JobName | Should -Be 'DBAOps - Nightly Backup'
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
                Mock Get-DbaAgentJobHistory -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            Status   = 'Failed'
                            Job      = 'DBAOps - Job A'
                            RunDate  = (Get-Date).AddHours(-1)
                            Duration = [timespan]::FromSeconds(10)
                            Message  = 'Failed.'
                        },
                        [PSCustomObject]@{
                            Status   = 'Succeeded'
                            Job      = 'DBAOps - Job B'
                            RunDate  = (Get-Date).AddHours(-1)
                            Duration = [timespan]::FromSeconds(5)
                            Message  = ''
                        },
                        [PSCustomObject]@{
                            Status   = 'Failed'
                            Job      = 'DBAOps - Excluded'
                            RunDate  = (Get-Date).AddHours(-1)
                            Duration = [timespan]::FromSeconds(3)
                            Message  = 'Failed.'
                        }
                    )
                }
            }
        }

        It 'Returns only failed jobs' {
            $result = Get-FailedJob -SqlInstance 'SQL01'
            $result | Should -Not -BeNullOrEmpty
            $result | ForEach-Object { $_.JobName | Should -Not -Be 'DBAOps - Job B' }
        }

        It 'Excludes jobs listed in ExcludeJob' {
            $result = Get-FailedJob -SqlInstance 'SQL01' -ExcludeJob 'DBAOps - Excluded'
            $result.JobName | Should -Not -Contain 'DBAOps - Excluded'
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
                Mock Get-DbaAgentJobHistory -RemoveParameterType 'SqlInstance' { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-FailedJob | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
