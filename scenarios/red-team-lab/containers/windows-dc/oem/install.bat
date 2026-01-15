@echo off
REM Red Team Training Lab - Windows DC Post-Install Script
REM This runs after Windows installation via dockur/windows OEM feature

echo === Red Team Training Lab - DC Setup ===
echo.

REM Set static IP (adjust for your network)
netsh interface ip set address "Ethernet" static 172.16.2.10 255.255.255.0 172.16.2.1
netsh interface ip set dns "Ethernet" static 127.0.0.1

REM Install AD DS role
echo Installing Active Directory Domain Services...
powershell -Command "Install-WindowsFeature AD-Domain-Services -IncludeManagementTools"

REM Copy setup scripts for manual execution
echo.
echo AD DS role installed.
echo.
echo NEXT STEPS (run manually after reboot):
echo 1. Run C:\setup\promote-dc.ps1 to promote to Domain Controller
echo 2. After reboot, run C:\setup\create-users.ps1 to create lab users
echo.

mkdir C:\setup 2>nul
copy /Y "%~dp0promote-dc.ps1" C:\setup\
copy /Y "%~dp0create-users.ps1" C:\setup\

echo Setup scripts copied to C:\setup\
pause
