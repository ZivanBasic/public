param(
  [string]$DomainName = "lab.local",
  [string]$SafeModeAdminPassword = "P@ssw0rd123!",
  [string]$LogFolder = "C:\install",
  [string]$LogFile = "Configure-ADDS.log"
)

# Ensure log dir + transcript
if (-not (Test-Path $LogFolder)) { New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null }
$LogPath = Join-Path $LogFolder $LogFile
Start-Transcript -Path $LogPath -Append

# Utilities
function Test-PendingReboot {
  $paths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
    'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
  )
  foreach ($p in $paths) { if (Test-Path $p) { return $true } }
  return $false
}

function Wait-ServicingReady {
  Write-Host "[$(Get-Date)] Waiting for Windows servicing to be ready…"
  $deadline = (Get-Date).AddMinutes(10)
  do {
    try {
      Get-WindowsFeature AD-Domain-Services -ErrorAction Stop | Out-Null
      if (-not (Test-PendingReboot)) { return }
      Write-Host "[$(Get-Date)] Reboot pending detected, waiting…"
    } catch {
      Write-Host "[$(Get-Date)] Servicing not ready yet: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 15
  } while ((Get-Date) -lt $deadline)
}

$scriptSelf = $PSCommandPath
$phaseFlag  = Join-Path $LogFolder 'adds.phase2.flag'

try {
  if (-not (Test-Path $phaseFlag)) {
    # ===== Phase 1: install role, then reboot =====
    Write-Host "[$(Get-Date)] Phase 1: Install AD DS role"
    Wait-ServicingReady

    $ok = $false
    for ($i=1; $i -le 5 -and -not $ok; $i++) {
      try {
        Write-Host "[$(Get-Date)] Attempt $i\: Install-WindowsFeature AD-Domain-Services…"
        Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -ErrorAction Stop | Out-Null
        $ok = $true
      } catch {
        Write-Warning "[$(Get-Date)] Install-WindowsFeature failed: $($_.Exception.Message)"
        Start-Sleep -Seconds (15 * $i)
      }
    }
    if (-not $ok) { throw "AD DS role failed to install after retries." }

    # Copy the script to a stable path and queue phase 2 on next boot
    $destScript = Join-Path $LogFolder (Split-Path $scriptSelf -Leaf)
    Copy-Item -Path $scriptSelf -Destination $destScript -Force
    Set-Content -Path $phaseFlag -Value "phase2" -Force | Out-Null

    $runOnceCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$destScript`" -DomainName `"$DomainName`" -SafeModeAdminPassword `"$SafeModeAdminPassword`""
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'FinishADDS' -Value $runOnceCmd -PropertyType String -Force | Out-Null

    Write-Host "[$(Get-Date)] Phase 1 complete. Rebooting now to continue with forest creation…"
    Restart-Computer -Force
    return
  }
  else {
    # ===== Phase 2: promote to domain controller =====
    Write-Host "[$(Get-Date)] Phase 2: Promote to DC for $DomainName"
    $secure = ConvertTo-SecureString $SafeModeAdminPassword -AsPlainText -Force

    Install-ADDSForest `
      -DomainName $DomainName `
      -DomainNetbiosName ($DomainName.Split('.')[0].ToUpper()) `
      -SafeModeAdministratorPassword $secure `
      -InstallDns:$true `
      -Force:$true `
      -NoRebootOnCompletion:$false
  }
}
catch {
  Write-Error "[$(Get-Date)] ERROR: $($_.Exception.Message)"
}
finally {
  Stop-Transcript
}
