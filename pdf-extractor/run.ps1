$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$bundledPython = 'C:\Users\PC\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$python = if ($env:APPSC_PYTHON) {
  $env:APPSC_PYTHON
} elseif (Test-Path -LiteralPath $bundledPython) {
  $bundledPython
} else {
  'python'
}

$env:PYTHONPATH = Join-Path $scriptDir '.python_packages'
Set-Location $scriptDir

& $python -m uvicorn app.main:app --host 127.0.0.1 --port 8001
