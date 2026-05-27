#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Find-ServerString' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Find-ServerString -SearchString 'test' -ErrorAction Stop } |
                Should -Throw
        }

        It 'Throws when SearchString is omitted' {
            { Find-ServerString -SqlInstance 'SQL01' -ErrorAction Stop } |
                Should -Throw
        }

        It 'Rejects an invalid Type value' {
            { Find-ServerString -SqlInstance 'SQL01' -SearchString 'test' -Type 'Tables' } |
                Should -Throw
        }

        It 'Accepts all valid Type values without throwing' {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance { [PSCustomObject]@{ ComputerName = 'SQL01'; InstanceName = 'MSSQLSERVER'; DomainInstanceName = 'SQL01' } }
                Mock Get-DbaDatabase     { @() }
                Mock Invoke-DbaQuery     { @() }
            }
            { Find-ServerString -SqlInstance 'SQL01' -SearchString 'test' `
                    -Type 'SqlModules', 'AgentJobs', 'LinkedServers' } |
                Should -Not -Throw
        }
    }

    Context 'SqlModules search' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Get-DbaDatabase {
                    @( [PSCustomObject]@{ Name = 'AppDB' } )
                }
                Mock Invoke-DbaQuery {
                    [PSCustomObject]@{
                        SchemaName = 'dbo'
                        ObjectName = 'usp_GetData'
                        ObjectType = 'SQL_STORED_PROCEDURE'
                        Definition = 'CREATE PROCEDURE dbo.usp_GetData AS SELECT oldserver'
                    }
                }
            }
        }

        It 'Returns a result with Type = SqlModule' {
            $result = Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' -Type SqlModules
            $result | Should -Not -BeNullOrEmpty
            $result.Type | Should -Be 'SqlModule'
        }

        It 'Populates ObjectName and SchemaName' {
            $result = Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' -Type SqlModules
            $result.ObjectName | Should -Be 'usp_GetData'
            $result.SchemaName | Should -Be 'dbo'
        }

        It 'Exposes MatchContext on the output object' {
            $result = Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' -Type SqlModules
            $result.MatchContext | Should -Not -BeNullOrEmpty
        }

        It 'Echoes SearchString on the output object' {
            $result = Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' -Type SqlModules
            $result.SearchString | Should -Be 'oldserver'
        }
    }

    Context 'AgentJobs search' {
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
                        JobName  = 'Nightly Backup'
                        StepID   = 1
                        StepName = 'Run backup'
                        DBName   = 'master'
                        Command  = 'EXEC sp_start_job oldserver'
                    }
                }
            }
        }

        It 'Returns a result with Type = AgentJob' {
            $result = Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' -Type AgentJobs
            $result | Should -Not -BeNullOrEmpty
            $result.Type | Should -Be 'AgentJob'
        }

        It 'Sets ObjectType to AgentJobStep' {
            $result = Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' -Type AgentJobs
            $result.ObjectType | Should -Be 'AgentJobStep'
        }

        It 'Includes job name and step number in ObjectName' {
            $result = Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' -Type AgentJobs
            $result.ObjectName | Should -BeLike '*Nightly Backup*'
            $result.ObjectName | Should -BeLike '*Step 1*'
        }
    }

    Context 'LinkedServers search' {
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
                        LinkedServerName = 'OLDSERVER'
                        Product          = 'SQL Server'
                        Provider         = 'SQLNCLI'
                        DataSource       = 'oldserver\inst'
                        Location         = ''
                    }
                }
            }
        }

        It 'Returns a result with Type = LinkedServer' {
            $result = Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' -Type LinkedServers
            $result | Should -Not -BeNullOrEmpty
            $result.Type | Should -Be 'LinkedServer'
        }

        It 'Sets ObjectType to LinkedServer' {
            $result = Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' -Type LinkedServers
            $result.ObjectType | Should -Be 'LinkedServer'
        }

        It 'Sets Database to null for server-level results' {
            $result = Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' -Type LinkedServers
            $result.Database | Should -BeNullOrEmpty
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
                Mock Get-DbaDatabase { @() }
                Mock Invoke-DbaQuery { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Find-ServerString -SearchString 'test' | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
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
                Mock Get-DbaDatabase {
                    @( [PSCustomObject]@{ Name = 'AppDB' } )
                }
                Mock Invoke-DbaQuery {
                    [PSCustomObject]@{
                        SchemaName = 'dbo'
                        ObjectName = 'usp_Test'
                        ObjectType = 'SQL_STORED_PROCEDURE'
                        Definition = 'oldserver'
                    }
                }
            }
        }

        It 'Has the correct PSTypeName' {
            $result = Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' -Type SqlModules
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.SearchResult'
        }

        It 'Has all expected properties' {
            $result = Find-ServerString -SqlInstance 'SQL01' -SearchString 'oldserver' -Type SqlModules
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'ComputerName'
            $props  | Should -Contain 'InstanceName'
            $props  | Should -Contain 'SqlInstance'
            $props  | Should -Contain 'Database'
            $props  | Should -Contain 'Type'
            $props  | Should -Contain 'SchemaName'
            $props  | Should -Contain 'ObjectName'
            $props  | Should -Contain 'ObjectType'
            $props  | Should -Contain 'MatchContext'
            $props  | Should -Contain 'SearchString'
        }
    }
}
