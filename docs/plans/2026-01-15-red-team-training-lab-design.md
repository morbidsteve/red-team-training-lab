# Red Team Training Lab Design

## Overview

A scalable cybersecurity training environment where students execute a full attack chain against a simulated small business network. Goal: teach defenders how attackers operate.

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           STUDENT ENVIRONMENT                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐                │
│  │   ATTACKER   │────▶│ REDIRECTOR 1 │────▶│ REDIRECTOR 2 │──────┐        │
│  │    (Kali)    │     │   (Alpine)   │     │   (Alpine)   │      │        │
│  └──────────────┘     └──────────────┘     └──────────────┘      │        │
│         │                                                         │        │
│         │ Internet-facing network (10.X.0.0/24)                  │        │
│         ▼                                                         ▼        │
│  ┌─────────────────────────────────────────────────────────────────┐      │
│  │                        ROUTEROS                                  │      │
│  │                   (VPN Concentrator)                            │      │
│  │              L2TP/IPSec + SSH Management                        │      │
│  └─────────────────────────────────────────────────────────────────┘      │
│         │                                    │                             │
│         │ DMZ (10.X.1.0/24)                 │ Internal (10.X.2.0/24)      │
│         ▼                                    ▼                             │
│  ┌──────────────┐                    ┌──────────────┐                     │
│  │  WORDPRESS   │                    │   WINDOWS    │                     │
│  │   + MySQL    │                    │      DC      │                     │
│  │  (SQLi/XSS)  │                    │  (AD, DNS)   │                     │
│  └──────────────┘                    └──────────────┘                     │
│         │                                    │                             │
│         │                            ┌──────────────┐                     │
│         │                            │  FILE SERVER │                     │
│         │                            │   (Samba)    │                     │
│         │                            │ Sensitive $  │                     │
│         └──────────────┬─────────────┴──────────────┘                     │
│                        │                                                   │
│                 ┌──────────────┐                                          │
│                 │  WORKSTATION │                                          │
│                 │  (Linux+GUI) │                                          │
│                 │  BeEF victim │                                          │
│                 └──────────────┘                                          │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘

X = student number (01-10)
```

### Network Segments

- **Internet (10.X.0.0/24)**: Attacker infrastructure, redirectors, external-facing services
- **DMZ (10.X.1.0/24)**: WordPress web server, exposed to internet
- **Internal (10.X.2.0/24)**: DC, file server, workstation - only reachable via VPN or pivot

## Attack Chain

### Phase 1: Reconnaissance
- Students scan from Kali through redirectors
- Discover WordPress on DMZ, RouterOS management interfaces
- Identify potential attack surfaces

### Phase 2a: SQL Injection → VPN Access
1. Exploit SQLi in vulnerable WordPress plugin (using sqlmap)
2. Dump `wp_users` table + any custom tables with credentials
3. Crack hashes offline (hashcat/john)
4. Discover credentials are reused for VPN
5. Connect L2TP tunnel through RouterOS → now on internal network

### Phase 2b: SSH Brute Force (parallel path)
1. Use dumped credentials/hashes against WordPress host SSH
2. Hydra spray against RouterOS SSH management
3. Gain shell on web server or router admin access

### Phase 2c: Client Exploitation
1. Inject BeEF hook into WordPress via stored XSS (or compromise site)
2. Internal workstation user browses to WordPress (simulated via script)
3. BeEF hooks browser → steal session cookies, keylog, redirect to credential harvester
4. Harvest internal user credentials

### Phase 3: Lateral Movement
- From VPN or compromised web server, pivot to internal network
- Enumerate AD (BloodHound, ldapsearch)
- Identify path to Domain Admin

### Phase 4: Effects Delivery
1. **Domain Dominance**: DCSync to dump all AD credentials, create backdoor admin
2. **Data Exfiltration**: Pull "sensitive" files from file share through redirectors
3. **Ransomware Simulation**: Encrypt files on share, drop ransom note

## Components

### Attacker Infrastructure

| Component | Base Image | Key Software | Purpose |
|-----------|------------|--------------|---------|
| Kali Attack Box | kalilinux/kali-rolling | sqlmap, hydra, hashcat, BeEF, Metasploit/Sliver, BloodHound, Impacket | Student's primary workstation |
| Redirector 1 | alpine:latest | socat, iptables | First hop, port forwarding |
| Redirector 2 | alpine:latest | nginx stream proxy | Second hop, C2 relay |

### Victim Network

| Component | Base Image | Key Software | Purpose |
|-----------|------------|--------------|---------|
| RouterOS | mikrotik/routeros (VM) | RouterOS v6.x | L2TP VPN, inter-VLAN routing, SSH target |
| WordPress Host | ubuntu:22.04 | Apache, PHP, MySQL, WordPress + vuln plugin | SQLi target, SSH brute force target, XSS injection point |
| Domain Controller | Windows Server 2019 (VM) | AD DS, DNS | Ultimate target, DCSync victim |
| File Server | ubuntu:22.04 | Samba, joined to AD | Sensitive data store, ransomware target |
| Workstation | Linux + Firefox | Browser, auto-browse script | BeEF hook victim |

## Directory Structure

```
red-team-lab/
├── docker-compose.yml          # Template with ${STUDENT_ID} variables
├── deploy.sh                   # Provisioning script
├── .env.template               # Environment template
│
├── infrastructure/
│   ├── kali/
│   │   └── Dockerfile          # Custom Kali with pre-installed tools
│   ├── redirector/
│   │   └── Dockerfile          # Alpine + socat/nginx
│   ├── wordpress/
│   │   ├── Dockerfile
│   │   └── vulnerable-plugin/  # Custom or known-vuln plugin
│   ├── fileserver/
│   │   ├── Dockerfile
│   │   └── sensitive-data/     # Fake PII, financials, etc.
│   └── workstation/
│       ├── Dockerfile
│       └── browse-script.py    # Auto-visits WordPress
│
├── vms/
│   ├── routeros/
│   │   └── packer.json         # RouterOS CHR template
│   └── windows/
│       ├── dc.pkr.hcl          # Windows Server DC template
│       └── workstation.pkr.hcl # Windows 10 (optional)
│
├── config/
│   ├── routeros.rsc            # RouterOS bootstrap config
│   ├── ad-setup.ps1            # AD users, groups, GPOs
│   └── credentials.yml         # Seed credentials (reused across systems)
│
└── docs/
    └── student-guide.md        # Attack walkthrough hints
```

## Deployment

### Provisioning Commands

```bash
# Create student environment
./deploy.sh create student01

# Tear down
./deploy.sh destroy student01

# Reset (destroy + create)
./deploy.sh reset student01

# Status check
./deploy.sh status
```

### Resource Requirements

Per student environment:
- Docker containers: ~4GB RAM
- RouterOS CHR: 256MB RAM
- Windows DC: 4GB RAM
- Workstation: 1GB RAM
- **Total: ~8-10GB RAM per student**

For 10 students: ~80-100GB RAM across hypervisor cluster.

## Student Experience

### Initial Access
```bash
ssh student01@lab-server -p 2201
# Lands in their Kali container
```

### Provided Information
- Target company: "Acme Widgets Inc." (small business)
- Known external IP range (DMZ-facing addresses)
- Mission objectives:
  1. Gain initial access to the network
  2. Obtain domain administrator privileges
  3. Exfiltrate sensitive business data
  4. Demonstrate ransomware impact
  5. Document attack chain

### Success Validation
Students prove completion by:
1. Submitting `Administrator` or `krbtgt` NTLM hash (domain dominance)
2. Providing contents of `//fileserver/sensitive/secret-formula.txt` (exfil)
3. Screenshot of ransom note on file share (ransomware)

## Technical Notes

- RouterOS: Use MikroTik Cloud Hosted Router (CHR) free tier or licensed
- Windows DC: Requires Windows Server license (eval versions work for training)
- BeEF victim: Headless Firefox with Selenium script that periodically visits WordPress
- Credential reuse: Same passwords seeded across WordPress, SSH, VPN, AD for realistic attack chain
