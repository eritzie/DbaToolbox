@{
    RootModule        = 'DbaToolbox.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'c4b3e444-2547-47cc-bea1-cf08acf4134b'
    Author            = 'Eric R'
    Description       = 'Personal PowerShell module complementing dbatools for SQL Server DBA workflows.'
    PowerShellVersion = '5.1'
    RequiredModules   = @('dbatools')
    FormatsToProcess  = @('DbaToolbox.Format.ps1xml')
    FunctionsToExport = @(
        'Find-ServerString'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('SQLServer', 'dbatools', 'DBA')
            ProjectUri = ''
        }
    }
}
