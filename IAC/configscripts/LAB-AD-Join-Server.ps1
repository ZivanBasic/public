param(
  [string]$DomainName = "lab.local",
  [string]$DomainJoinUser = "LAB\\Administrator",   # or 'Administrator@lab.local'
  [string]$DomainJoinPassword = "P@ssw0rd123!",     # pass via secure pipeline var ideally
  [string]$DcIp = "10.12.0.4",                      # DC NIC IP (optional but recommended in lab)
  [string]$LogFolder = "C:\install",
  [string]$LogFile = "Join-Domain.log"
)

# Ensure log dir + start transcript
if (-not (Test-Path $LogFolder)) { New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null }
$LogPath = Join-Path $LogFolder $LogFile
Start-Transcript -Path $LogPath -Append

function Set-LabDns {
  param([string]$Ip)
  Write-Host "Setting NIC DNS servers to $Ip"
  Get-DnsClient |
    Where-Object { $_.InterfaceAlias -notmatch 'Loopback|isatap|Teredo' } |
    ForEach-Object {
      try {
        Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses $Ip -ErrorAction Stop
        Write-Host "DNS set on interface '$($_.InterfaceAlias)'"
      } catch {
        Write-Warning "Failed to set DNS on '$($_.InterfaceAlias)': $($_.Exception.Message)"
      }
    }
}

function Test-DomainReady {
  param([string]$Domain,[string]$DnsIp)
  try {
    if ($DnsIp) {
      Resolve-DnsName -Type SRV -Name ("_ldap._tcp.dc._msdcs.{0}" -f $Domain) -Server $DnsIp -ErrorAction Stop | Out-Null
    } else {
      Resolve-DnsName -Type SRV -Name ("_ldap._tcp.dc._msdcs.{0}" -f $Domain) -ErrorAction Stop | Out-Null
    }
    return $true
  } catch { return $false }
}

try {
  # Skip if already joined
  $cs = Get-CimInstance Win32_ComputerSystem
  if ($cs.PartOfDomain -and $cs.Domain -ieq $DomainName) {
    Write-Host "Already joined to $($cs.Domain). Nothing to do."
    return
  }

  if ($DcIp) { Set-LabDns -Ip $DcIp }

  # Wait up to 10 minutes for domain/DNS to come online
  $deadline = (Get-Date).AddMinutes(10)
  while ((Get-Date) -lt $deadline) {
    if (Test-DomainReady -Domain $DomainName -DnsIp $DcIp) {
      Write-Host "Domain DNS looks ready."
      break
    }
    Write-Host "Waiting for domain DNS…"
    Start-Sleep -Seconds 10
  }

  # Prepare credentials
  $sec = ConvertTo-SecureString $DomainJoinPassword -AsPlainText -Force
  $cred = New-Object System.Management.Automation.PSCredential ($DomainJoinUser, $sec)

  Write-Host "Joining $env:COMPUTERNAME to $DomainName..."
  Add-Computer -DomainName $DomainName -Credential $cred -ErrorAction Stop -Force -Restart
}
catch {
  Write-Error "Join failed: $($_.Exception.Message)"
}
finally {
  Stop-Transcript
}
