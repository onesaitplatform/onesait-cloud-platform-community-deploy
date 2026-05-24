# start.ps1 - Start OnesaitPlatform after a WSL2 reboot or after stopping containers
# Run from Windows PowerShell or Windows Terminal

$ErrorActionPreference = "Stop"

Write-Host "========================================================" -ForegroundColor Blue
Write-Host "  OnesaitPlatform - Start                              " -ForegroundColor Blue
Write-Host "========================================================" -ForegroundColor Blue
Write-Host ""

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: WSL not found." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

$wslScriptDir = "~/personal-projects/onesait-platform-deploy"

Write-Host "Starting OnesaitPlatform in WSL2..." -ForegroundColor Yellow
Write-Host ""

wsl bash -c "cd $wslScriptDir && chmod +x start.sh && ./start.sh"

if ($LASTEXITCODE -eq 0) {
    $wslIp = (wsl bash -c "hostname -I") -split '\s+' | Where-Object { $_ -ne '' } | Select-Object -First 1
    $url = "https://$wslIp/controlpanel/"

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host "  OnesaitPlatform is up!                               " -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "URL: $url" -ForegroundColor Cyan
    Write-Host "(Use InPrivate/Incognito window if you see redirect errors)" -ForegroundColor Yellow
    Write-Host ""

    $openBrowser = Read-Host "Open browser now? [Y/n]"
    if ($openBrowser -ne 'n' -and $openBrowser -ne 'N') {
        Start-Process $url
    }
} else {
    Write-Host ""
    Write-Host "ERROR: start.sh exited with errors. Check the output above." -ForegroundColor Red
    Read-Host "Press Enter to close"
}
