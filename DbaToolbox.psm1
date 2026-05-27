$script:ModuleRoot = $PSScriptRoot

Get-ChildItem -Path "$PSScriptRoot\functions" -Filter '*.ps1' | ForEach-Object {
    . $_.FullName
}
