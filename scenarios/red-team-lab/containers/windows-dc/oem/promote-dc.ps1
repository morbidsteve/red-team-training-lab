# Red Team Training Lab - Promote to Domain Controller
# Run this after install.bat

$DomainName = "acmewidgets.local"
$NetBiosName = "ACME"
$SafeModePassword = ConvertTo-SecureString "SafeMode2024!" -AsPlainText -Force

Write-Host "=== Promoting to Domain Controller ===" -ForegroundColor Cyan
Write-Host "Domain: $DomainName"
Write-Host ""

Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetBiosName `
    -SafeModeAdministratorPassword $SafeModePassword `
    -InstallDNS `
    -Force

Write-Host ""
Write-Host "Server will restart. Run create-users.ps1 after reboot." -ForegroundColor Green
