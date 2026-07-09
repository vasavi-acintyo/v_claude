# setup-ssh.ps1
# Generates an ED25519 SSH key, adds it to ssh-agent, copies public key to clipboard,
# and opens the GitHub SSH key page for you to paste the key.

param()

$keyPath = "$env:USERPROFILE\.ssh\id_ed25519"
$pubPath = "$keyPath.pub"
$email = "shiv@acintyotech.ai"

Write-Host "SSH setup script started" -ForegroundColor Cyan

# Ensure .ssh exists
if (-not (Test-Path (Split-Path $keyPath))) {
  New-Item -ItemType Directory -Path (Split-Path $keyPath) | Out-Null
}

# Generate key if it doesn't exist
if (Test-Path $keyPath) {
  Write-Host "Key already exists at $keyPath" -ForegroundColor Yellow
  $answer = Read-Host "Overwrite existing key? (y/N)"
  if ($answer -ne 'y' -and $answer -ne 'Y') {
    Write-Host "Skipping key generation." -ForegroundColor Yellow
  } else {
    Remove-Item $keyPath -Force -ErrorAction SilentlyContinue
    Remove-Item $pubPath -Force -ErrorAction SilentlyContinue
    ssh-keygen -t ed25519 -C $email -f $keyPath -N "" | Out-Null
  }
} else {
  ssh-keygen -t ed25519 -C $email -f $keyPath -N "" | Out-Null
}

# Ensure ssh-agent running
Write-Host "Starting ssh-agent (will require admin to set service StartupType if not set)" -ForegroundColor Cyan
Try {
  Set-Service -Name ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue
  Start-Service ssh-agent -ErrorAction SilentlyContinue
} Catch {
  Write-Host "Could not start ssh-agent service automatically. If this fails, start it manually." -ForegroundColor Yellow
}

# Add key to agent
ssh-add $keyPath 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host "ssh-add returned non-zero exit code - you may need to run PowerShell as Administrator or start the agent manually." -ForegroundColor Yellow
}

# Copy public key to clipboard
if (Test-Path $pubPath) {
  Get-Content $pubPath | Set-Clipboard
  Write-Host "Public key copied to clipboard." -ForegroundColor Green
} else {
  Write-Host "Public key not found at $pubPath" -ForegroundColor Red
}

# Open GitHub SSH key page
Start-Process "https://github.com/settings/ssh/new"

# Test connection (non-interactive; show result)
Write-Host "Testing SSH connection to GitHub..." -ForegroundColor Cyan
ssh -T git@github.com 2>&1 | ForEach-Object { Write-Host $_ }

Write-Host 'If authentication succeeded you will see a message starting with Hi. Paste the public key into GitHub and then retry: git push -u origin main.' -ForegroundColor Cyan
