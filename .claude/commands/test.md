# /test

Run the full Pester test suite.

```powershell
Invoke-Pester $ARGUMENTS .\tests\ -Output Detailed
```

Usage:
- `/test` — run all tests
- `/test .\tests\Find-ServerString.Tests.ps1` — run a single file
