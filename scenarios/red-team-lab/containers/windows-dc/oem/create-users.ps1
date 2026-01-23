# Red Team Training Lab - Create AD Users
# Run after DC promotion and reboot

Write-Host "=== Creating Lab Users ===" -ForegroundColor Cyan

Import-Module ActiveDirectory

# Wait for AD DS
while (-not (Get-Service NTDS -ErrorAction SilentlyContinue).Status -eq "Running") {
    Write-Host "Waiting for AD DS..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
}

# Create OUs
New-ADOrganizationalUnit -Name "AcmeUsers" -Path "DC=acmewidgets,DC=local" -ErrorAction SilentlyContinue
New-ADOrganizationalUnit -Name "ServiceAccounts" -Path "DC=acmewidgets,DC=local" -ErrorAction SilentlyContinue

# Create Groups
New-ADGroup -Name "IT Support" -GroupScope Global -Path "OU=AcmeUsers,DC=acmewidgets,DC=local" -ErrorAction SilentlyContinue
New-ADGroup -Name "Accounting" -GroupScope Global -Path "OU=AcmeUsers,DC=acmewidgets,DC=local" -ErrorAction SilentlyContinue

# Create Users
$users = @(
    @{ Name="John Smith"; Sam="jsmith"; Pass="Summer2024"; Groups=@("IT Support") },
    @{ Name="Mary Williams"; Sam="mwilliams"; Pass="Welcome123"; Groups=@("Accounting") },
    @{ Name="Backup Service"; Sam="svc_backup"; Pass="Backup2024"; Groups=@(); ServiceAccount=$true }
)

foreach ($user in $users) {
    $securePass = ConvertTo-SecureString $user.Pass -AsPlainText -Force
    $path = if ($user.ServiceAccount) { "OU=ServiceAccounts,DC=acmewidgets,DC=local" } else { "OU=AcmeUsers,DC=acmewidgets,DC=local" }

    New-ADUser -Name $user.Name -SamAccountName $user.Sam `
        -UserPrincipalName "$($user.Sam)@acmewidgets.local" `
        -AccountPassword $securePass -Enabled $true `
        -PasswordNeverExpires $true -Path $path -ErrorAction SilentlyContinue

    foreach ($group in $user.Groups) {
        Add-ADGroupMember -Identity $group -Members $user.Sam -ErrorAction SilentlyContinue
    }
    Write-Host "Created: $($user.Sam)" -ForegroundColor Green
}

# MISCONFIGURATION: Give svc_backup DCSync rights
Write-Host ""
Write-Host "Configuring misconfiguration for training..." -ForegroundColor Yellow

$acl = Get-Acl "AD:\DC=acmewidgets,DC=local"
$svcBackupSid = (Get-ADUser svc_backup).SID

# Replicating Directory Changes and Replicating Directory Changes All
$replicatingChanges = [GUID]"1131f6aa-9c07-11d1-f79f-00c04fc2dcd2"
$replicatingChangesAll = [GUID]"1131f6ad-9c07-11d1-f79f-00c04fc2dcd2"

$ace1 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($svcBackupSid, "ExtendedRight", "Allow", $replicatingChanges)
$ace2 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($svcBackupSid, "ExtendedRight", "Allow", $replicatingChangesAll)

$acl.AddAccessRule($ace1)
$acl.AddAccessRule($ace2)
Set-Acl "AD:\DC=acmewidgets,DC=local" $acl

Write-Host "svc_backup now has DCSync rights (MISCONFIGURATION)" -ForegroundColor Red

# Set Administrator password
$adminPass = ConvertTo-SecureString "Adm1n2024" -AsPlainText -Force
Set-ADAccountPassword -Identity Administrator -NewPassword $adminPass -Reset

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host "Domain: acmewidgets.local"
Write-Host "Admin password: Adm1n2024"
Write-Host ""
Write-Host "Vulnerable configs:" -ForegroundColor Yellow
Write-Host "  - svc_backup has DCSync rights"
Write-Host "  - Users have weak, reused passwords"
