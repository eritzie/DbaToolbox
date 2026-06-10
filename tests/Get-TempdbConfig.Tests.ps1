#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot\..\DbaToolbox.psd1" -Force
}

Describe 'Get-TempdbConfig' {

    Context 'Parameter validation' {
        It 'Throws when SqlInstance is omitted' {
            { Get-TempdbConfig -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Best practice output (TempdbBestPractice)' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Test-DbaTempDbConfig {
                    @(
                        [PSCustomObject]@{
                            Rule           = 'TF 1118 Enabled'
                            CurrentSetting = 'False'
                            Recommended    = 'True'
                            IsBestPractice = $false
                            Notes          = 'Enable trace flag 1118'
                        }
                    )
                }
                Mock Invoke-DbaQuery { @() }
            }
        }

        It 'Emits TempdbBestPractice rows' {
            $result = Get-TempdbConfig -SqlInstance 'SQL01' |
                Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.TempdbBestPractice' }
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.TempdbBestPractice'
        }

        It 'Has all required TempdbBestPractice properties' {
            $result = Get-TempdbConfig -SqlInstance 'SQL01' |
                Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.TempdbBestPractice' }
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'ComputerName'
            $props  | Should -Contain 'InstanceName'
            $props  | Should -Contain 'SqlInstance'
            $props  | Should -Contain 'Rule'
            $props  | Should -Contain 'CurrentSetting'
            $props  | Should -Contain 'Recommended'
            $props  | Should -Contain 'IsBestPractice'
        }
    }

    Context 'File detail output (TempdbFile)' {
        BeforeAll {
            InModuleScope DbaToolbox {
                Mock Connect-DbaInstance {
                    [PSCustomObject]@{
                        ComputerName       = 'SQL01'
                        InstanceName       = 'MSSQLSERVER'
                        DomainInstanceName = 'SQL01'
                    }
                }
                Mock Test-DbaTempDbConfig { @() }
                Mock Invoke-DbaQuery {
                    [PSCustomObject]@{
                        FileName     = 'tempdev'
                        FileType     = 'ROWS'
                        SizeMB       = 8192
                        FreeMB       = 4096
                        FreePct      = 50.0
                        AutoGrowth   = '512 MB'
                        PhysicalPath = 'E:\MSSQL\DATA\tempdb.mdf'
                    }
                }
            }
        }

        It 'Emits TempdbFile rows' {
            $result = Get-TempdbConfig -SqlInstance 'SQL01' |
                Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.TempdbFile' }
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.TypeNames[0] | Should -Be 'DbaToolbox.TempdbFile'
        }

        It 'Has all required TempdbFile properties' {
            $result = Get-TempdbConfig -SqlInstance 'SQL01' |
                Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.TempdbFile' }
            $props  = $result.PSObject.Properties.Name
            $props  | Should -Contain 'FileName'
            $props  | Should -Contain 'FileType'
            $props  | Should -Contain 'SizeMB'
            $props  | Should -Contain 'FreeMB'
            $props  | Should -Contain 'FreePct'
            $props  | Should -Contain 'AutoGrowth'
            $props  | Should -Contain 'PhysicalPath'
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
                Mock Test-DbaTempDbConfig { @() }
                Mock Invoke-DbaQuery { @() }
            }
        }

        It 'Connects once per piped instance' {
            'SQL01', 'SQL02' | Get-TempdbConfig | Out-Null
            Should -Invoke Connect-DbaInstance -ModuleName DbaToolbox -Times 2 -Exactly
        }
    }
}
