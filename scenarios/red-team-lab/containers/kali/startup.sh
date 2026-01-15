#!/bin/bash
# Kali Attack Box - Startup Script

# Create convenient symlinks
ln -sf /usr/share/wordlists ~/wordlists 2>/dev/null
ln -sf /usr/share/seclists ~/seclists 2>/dev/null

# Create a desktop shortcut for terminal
mkdir -p ~/Desktop
cat > ~/Desktop/Terminal.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Terminal
Exec=xfce4-terminal
Icon=utilities-terminal
Terminal=false
EOF
chmod +x ~/Desktop/Terminal.desktop

# Create quick reference on desktop
cat > ~/Desktop/README.txt << 'EOF'
=== Red Team Training Lab - Kali Attack Box ===

Target Network:
  - Webserver (WordPress): 172.16.1.10
  - Domain Controller:     172.16.2.10
  - File Server:           172.16.2.20
  - Workstation:           172.16.2.30

Quick Start Commands:
  nmap -sV 172.16.1.10          # Scan webserver
  sqlmap -u "URL" --dbs         # SQL injection
  smbclient -L //172.16.2.20    # List SMB shares
  impacket-secretsdump          # DCSync attack

See STUDENT-GUIDE.md for full walkthrough!
EOF

echo "[+] Kali Attack Box initialized"
