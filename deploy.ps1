# deploy.ps1 - First-time deployment of OnesaitPlatform via WSL2
# Run from Windows PowerShell or Windows Terminal (right-click > Run with PowerShell)

$ErrorActionPreference = "Stop"

Write-Host "========================================================" -ForegroundColor Blue
Write-Host "  OnesaitPlatform - First-time Deploy                  " -ForegroundColor Blue
Write-Host "========================================================" -ForegroundColor Blue
Write-Host ""

# Verify WSL is available
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: WSL not found. Install WSL2 first: https://aka.ms/wsl2" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

$wslScriptDir = "~/personal-projects/onesait-platform-deploy"

Write-Host "Launching deploy.sh in WSL2..." -ForegroundColor Yellow
Write-Host "(Answer the prompts in the terminal below)" -ForegroundColor Cyan
Write-Host ""

# Run deploy.sh interactively in WSL (stdin/stdout pass through to this terminal)
wsl bash -c "cd $wslScriptDir && chmod +x deploy.sh && ./deploy.sh"

if ($LASTEXITCODE -eq 0) {
    # Get WSL2 IP after deployment completes
    $wslIp = (wsl bash -c "hostname -I") -split '\s+' | Where-Object { $_ -ne '' } | Select-Object -First 1
    $url = "https://$wslIp/controlpanel/"

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host "  Deployment complete!                                  " -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Opening browser at: $url" -ForegroundColor Cyan
    Write-Host "(Accept the self-signed certificate warning in your browser)" -ForegroundColor Yellow
    Write-Host ""

    Start-Sleep -Seconds 3
    Start-Process $url
} else {
    Write-Host ""
    Write-Host "ERROR: deploy.sh exited with errors. Check the output above." -ForegroundColor Red
}

Read-Host "Press Enter to close"
