# stop.ps1 - Stop all OnesaitPlatform containers
# Run from Windows PowerShell or Windows Terminal

$ErrorActionPreference = "Stop"

Write-Host "========================================================" -ForegroundColor Red
Write-Host "  OnesaitPlatform - Stop                               " -ForegroundColor Red
Write-Host "========================================================" -ForegroundColor Red
Write-Host ""

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: WSL not found." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

$wslScriptDir = "~/personal-projects/onesait-platform-deploy"

$confirm = Read-Host "Stop all OnesaitPlatform containers? [Y/n]"
if ($confirm -eq 'n' -or $confirm -eq 'N') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Stopping all containers..." -ForegroundColor Yellow

wsl bash -c "cd $wslScriptDir && chmod +x stop.sh && ./stop.sh"

Write-Host ""
if ($LASTEXITCODE -eq 0) {
    Write-Host "All containers stopped." -ForegroundColor Green
} else {
    Write-Host "stop.sh finished with warnings. Check the output above." -ForegroundColor Yellow
}

Read-Host "Press Enter to close"
