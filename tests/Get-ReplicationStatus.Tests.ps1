#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-ReplicationStatus' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-ReplicationStatus -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Output types' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                # Mirrors Get-DbaReplPublication default view: DatabaseName, Name, Type,
                # Articles (collection), Subscriptions (collection)
                Mock Get-DbaReplPublication -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            DatabaseName  = 'AppDB'
                            Name          = 'AppDB_Pub'
                            Type          = 'Transactional'
                            Articles      = @('t1', 't2', 't3')
                            Subscriptions = @('sub1')
                        }
                    )
                }
                # Mirrors Get-DbaReplSubscription default view
                Mock Get-DbaReplSubscription -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            DatabaseName       = 'AppDB'
                            PublicationName    = 'AppDB_Pub'
                            Name               = 'AppDB_Sub'
                            SubscriberName     = 'SQL-SUB01'
                            SubscriptionDBName = 'AppDB_Replica'
                            SubscriptionType   = 'Push'
                        }
                    )
                }
            }
        }

        It 'Emits ReplPublication rows with counts' {
            $result = Get-ReplicationStatus -SqlInstance 'SQL01' |
                Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.ReplPublication' }
            $result | Should -Not -BeNullOrEmpty
            $result.PublicationName | Should -Be 'AppDB_Pub'
            $result.ArticleCount | Should -Be 3
            $result.SubscriptionCount | Should -Be 1
        }

        It 'Emits ReplSubscription rows' {
            $result = Get-ReplicationStatus -SqlInstance 'SQL01' |
                Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.ReplSubscription' }
            $result | Should -Not -BeNullOrEmpty
            $result.SubscriberName | Should -Be 'SQL-SUB01'
            $result.SubscriptionDb | Should -Be 'AppDB_Replica'
            $result.SubscriptionType | Should -Be 'Push'
        }
    }

    Context 'No replication configured' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Get-DbaReplPublication -RemoveParameterType 'SqlInstance' { @() }
                Mock Get-DbaReplSubscription -RemoveParameterType 'SqlInstance' { @() }
            }
        }

        It 'Returns nothing on an instance without replication' {
            $result = Get-ReplicationStatus -SqlInstance 'SQL01'
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
                Mock Get-DbaReplPublication -RemoveParameterType 'SqlInstance' { @() }
                Mock Get-DbaReplSubscription -RemoveParameterType 'SqlInstance' { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-ReplicationStatus | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
