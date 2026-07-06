#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-AgHealth' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-AgHealth -ErrorAction Stop } | Should -Throw
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
                # Mirrors Get-DbaAgReplica default view properties
                Mock Get-DbaAgReplica -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            AvailabilityGroup          = 'AG1'
                            Name                       = 'SQL01'
                            Role                       = 'Primary'
                            ConnectionState            = 'Connected'
                            RollupSynchronizationState = 'Synchronized'
                            AvailabilityMode           = 'SynchronousCommit'
                            FailoverMode               = 'Automatic'
                        }
                    )
                }
                # Mirrors Get-DbaAgDatabaseReplicaState output properties
                Mock Get-DbaAgDatabaseReplicaState -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            AvailabilityGroup        = 'AG1'
                            ReplicaServerName        = 'SQL02'
                            ReplicaRole              = 'Secondary'
                            AvailabilityDatabaseName = 'AppDB'
                            SynchronizationState     = 'Synchronized'
                            IsSuspended              = $false
                            SuspendReason            = 'NotApplicable'
                            LogSendQueueSize         = 0
                            RedoQueueSize            = 12
                            EstimatedDataLoss        = 0
                            LastCommitTime           = [datetime]'2026-07-06 10:00:00'
                        }
                    )
                }
            }
        }

        It 'Emits AgReplicaHealth rows' {
            $result = Get-AgHealth -SqlInstance 'SQL01' |
                Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.AgReplicaHealth' }
            $result | Should -Not -BeNullOrEmpty
            $result.ReplicaName | Should -Be 'SQL01'
            $result.Role | Should -Be 'Primary'
        }

        It 'Emits AgDatabaseHealth rows' {
            $result = Get-AgHealth -SqlInstance 'SQL01' |
                Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.AgDatabaseHealth' }
            $result | Should -Not -BeNullOrEmpty
            $result.DatabaseName | Should -Be 'AppDB'
            $result.RedoQueueKB | Should -Be 12
        }

        It 'AgDatabaseHealth has all required properties' {
            $result = Get-AgHealth -SqlInstance 'SQL01' |
                Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.AgDatabaseHealth' }
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'AvailabilityGroup'
            $props  | Should -Contain 'ReplicaName'
            $props  | Should -Contain 'ReplicaRole'
            $props  | Should -Contain 'DatabaseName'
            $props  | Should -Contain 'SynchronizationState'
            $props  | Should -Contain 'IsSuspended'
            $props  | Should -Contain 'SuspendReason'
            $props  | Should -Contain 'LogSendQueueKB'
            $props  | Should -Contain 'RedoQueueKB'
            $props  | Should -Contain 'EstimatedDataLossSec'
            $props  | Should -Contain 'LastCommitTime'
        }

        It 'Passes AvailabilityGroup filter through' {
            Get-AgHealth -SqlInstance 'SQL01' -AvailabilityGroup 'AG1' | Out-Null
            Should -Invoke Get-DbaAgReplica -ModuleName DbaToolbox -Times 1 -Exactly -ParameterFilter {
                $AvailabilityGroup -eq 'AG1'
            }
        }
    }

    Context 'No availability groups' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Get-DbaAgReplica -RemoveParameterType 'SqlInstance' { @() }
                Mock Get-DbaAgDatabaseReplicaState -RemoveParameterType 'SqlInstance' { @() }
            }
        }

        It 'Returns nothing on an instance without AGs' {
            $result = Get-AgHealth -SqlInstance 'SQL01'
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
                Mock Get-DbaAgReplica -RemoveParameterType 'SqlInstance' { @() }
                Mock Get-DbaAgDatabaseReplicaState -RemoveParameterType 'SqlInstance' { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-AgHealth | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
