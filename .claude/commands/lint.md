# /lint

Run PSScriptAnalyzer against all functions.

```powershell
Invoke-ScriptAnalyzer -Path .\functions\ -Recurse -Severity Warning
```

Must return no warnings before a function is considered production-ready.
