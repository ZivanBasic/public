param (
    [string]$DomainName = "lab.local",
    [string]$SafeModeAdminPassword = "P@ssw0rd123!",
    [string]$LogFolder = "C:\install",
    [string]$LogFile = "Configure-ADDS.log"
)

# Ensure log folder exists
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

$LogPath = Join-Path $LogFolder $LogFile

# Start logging
Start-Transcript -Path $LogPath -Append

try {
    Write-Host "[$(Get-Date)] Installing AD DS role..."
    Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

    Write-Host "[$(Get-Date)] Promoting server to Domain Controller for $DomainName..."
    $securePassword = ConvertTo-SecureString $SafeModeAdminPassword -AsPlainText -Force

    Install-ADDSForest `
        -DomainName $DomainName `
        -SafeModeAdministratorPassword $securePassword `
        -DomainNetbiosName "LAB" `
        -InstallDns:$true `
        -Force:$true `
        -NoRebootOnCompletion:$false
}
catch {
    Write-Error "[$(Get-Date)] ERROR: $($_.Exception.Message)"
}
finally {
    Stop-Transcript
}
