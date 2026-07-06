#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-DatabaseSize' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-DatabaseSize -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Summary output (DatabaseSize)' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Get-DbaDbFile -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            Database              = 'AppDB'
                            LogicalName           = 'AppDB'
                            TypeDescription       = 'ROWS'
                            Size                  = 5368709120   # 5 GB
                            UsedSpace             = 4294967296   # 4 GB
                            AvailableSpace        = 1073741824   # 1 GB
                            GrowthType            = 'KB'
                            Growth                = 524288
                            NextGrowthEventSize   = 536870912
                            PhysicalName          = 'E:\Data\AppDB.mdf'
                        },
                        [PSCustomObject]@{
                            Database              = 'AppDB'
                            LogicalName           = 'AppDB_log'
                            TypeDescription       = 'LOG'
                            Size                  = 1073741824   # 1 GB
                            UsedSpace             = 536870912    # 512 MB
                            AvailableSpace        = 536870912    # 512 MB
                            GrowthType            = 'KB'
                            Growth                = 131072
                            NextGrowthEventSize   = 134217728
                            PhysicalName          = 'L:\Log\AppDB_log.ldf'
                        }
                    )
                }
            }
        }

        It 'Returns DbaToolbox.DatabaseSize by default' {
            $result = Get-DatabaseSize -SqlInstance 'SQL01'
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.DatabaseSize'
        }

        It 'Has all required DatabaseSize properties' {
            $result = Get-DatabaseSize -SqlInstance 'SQL01'
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'ComputerName'
            $props  | Should -Contain 'InstanceName'
            $props  | Should -Contain 'SqlInstance'
            $props  | Should -Contain 'DatabaseName'
            $props  | Should -Contain 'TotalSizeMB'
            $props  | Should -Contain 'UsedMB'
            $props  | Should -Contain 'FreeMB'
            $props  | Should -Contain 'UsedPct'
        }

        It 'Groups files into a single summary row per database' {
            $result = Get-DatabaseSize -SqlInstance 'SQL01'
            @($result).Count | Should -Be 1
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.DatabaseSize'
        }

        It 'Does not emit DatabaseFile rows without -IncludeFiles' {
            $result = Get-DatabaseSize -SqlInstance 'SQL01'
            $fileRows = $result | Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.DatabaseFile' }
            $fileRows | Should -BeNullOrEmpty
        }
    }

    Context 'File detail output (DatabaseFile) with -IncludeFiles' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Get-DbaDbFile -RemoveParameterType 'SqlInstance' {
                    @(
                        [PSCustomObject]@{
                            Database              = 'AppDB'
                            LogicalName           = 'AppDB'
                            TypeDescription       = 'ROWS'
                            Size                  = 5368709120
                            UsedSpace             = 4294967296
                            AvailableSpace        = 1073741824
                            GrowthType            = 'Percent'
                            Growth                = 10
                            NextGrowthEventSize   = 536870912
                            PhysicalName          = 'E:\Data\AppDB.mdf'
                        }
                    )
                }
            }
        }

        It 'Emits DatabaseFile rows with -IncludeFiles' {
            $result = Get-DatabaseSize -SqlInstance 'SQL01' -IncludeFiles
            $fileRows = $result | Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.DatabaseFile' }
            $fileRows | Should -Not -BeNullOrEmpty
        }

        It 'Flags percentage-based autogrowth with asterisk' {
            $result   = Get-DatabaseSize -SqlInstance 'SQL01' -IncludeFiles
            $fileRow  = $result | Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.DatabaseFile' }
            $fileRow.AutoGrowth | Should -BeLike '*%*'
        }

        It 'Has all required DatabaseFile properties' {
            $result  = Get-DatabaseSize -SqlInstance 'SQL01' -IncludeFiles
            $fileRow = $result | Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.DatabaseFile' }
            $props   = $fileRow.PSObject.Properties.Name
            $props   | Should -Contain 'DatabaseName'
            $props   | Should -Contain 'LogicalName'
            $props   | Should -Contain 'TypeDescription'
            $props   | Should -Contain 'SizeMB'
            $props   | Should -Contain 'UsedMB'
            $props   | Should -Contain 'FreeMB'
            $props   | Should -Contain 'UsedPct'
            $props   | Should -Contain 'AutoGrowth'
            $props   | Should -Contain 'PhysicalName'
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
                Mock Get-DbaDbFile -RemoveParameterType 'SqlInstance' { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-DatabaseSize | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
