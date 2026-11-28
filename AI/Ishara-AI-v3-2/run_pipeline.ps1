# run_pipeline.ps1 — نفس run_pipeline.py على Windows، بـ Python بتاع الـ venv (.venv\Scripts\python.exe)
#   .\run_pipeline.ps1
#   .\run_pipeline.ps1 --kit D:\Ishara-Mobile-Kit
# لو PowerShell رفض يشغّل السكريبت (ExecutionPolicy):
#   powershell -ExecutionPolicy Bypass -File .\run_pipeline.ps1
$py = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path $py)) {
    Write-Host "مش لاقي $py. اعمل الـ venv الأول (شوف README.md: التسطيب على Windows)."
    exit 1
}
& $py (Join-Path $PSScriptRoot 'run_pipeline.py') @args
exit $LASTEXITCODE
