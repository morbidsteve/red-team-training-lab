# Red Team Training Lab

A complete attack training environment for CYROID. Students learn offensive security by executing a full attack chain against a simulated small business network.

## Platform Support

The lab runs on **both macOS and Linux**:

| Platform | Domain Controller | Notes |
|----------|------------------|-------|
| **macOS** | Samba AD DC (automatic) | Full functionality, no KVM required |
| **Linux with KVM** | Windows DC (default) | Most realistic, uses hardware acceleration |
| **Linux with KVM** | Samba AD DC (optional) | Set `USE_SAMBA_DC=true` for faster setup |
| **Linux without KVM** | Samba AD DC (automatic) | Falls back automatically |

Both DC options support the same attack scenarios: DCSync, Pass-the-Hash, BloodHound enumeration, and credential reuse attacks.

## Attack Scenarios

| Phase | Technique | Target | Outcome |
|-------|-----------|--------|---------|
| Initial Access | SQL Injection | WordPress | Credential dump |
| Initial Access | SSH Brute Force | Web server | Shell access |
| Initial Access | BeEF + XSS | Workstation | Browser hook |
| Lateral Movement | VPN with stolen creds | RouterOS | Internal access |
| Privilege Escalation | DCSync | Domain Controller | Domain Admin |
| Impact | Data Exfil + Ransomware | File Server | Mission complete |

## Network Topology

```
ATTACKER (Kali)
    │
    ├── Redirector 1 ──── Redirector 2
    │
    ▼
┌─────────────────────────────────────────┐
│           INTERNET (172.16.0.0/24)      │
│  WordPress ◄───────────────────────────────── SQLi Target
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│             DMZ (172.16.1.0/24)         │
│  Workstation ◄─────────────────────────────── BeEF Victim
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│          INTERNAL (172.16.2.0/24)       │
│  DC + File Server ◄────────────────────────── Final Target
└─────────────────────────────────────────┘
```

## Deployment Options

### Option 1: One-Click Blueprint Import (Recommended)

The easiest way - import the pre-built blueprint directly into CYROID:

1. **Build the container images** (one-time setup):
   ```bash
   cd scenarios/red-team-lab
   ./deploy/build-local.sh
   ```

2. **Import the blueprint** in CYROID UI:
   - Go to **Blueprints** → **Import**
   - Upload `red-team-training-lab.blueprint.zip` from this repo
   - Click **Import**

3. **Deploy an instance**:
   - Click **Deploy** on the imported blueprint
   - Name your range (e.g., "Student 1")
   - Check "Auto-deploy" and click **Create**

That's it! The range will deploy with all 7 VMs and proper networking.

### Option 2: API Import

If you prefer command-line:

```bash
# 1. Build container images
cd scenarios/red-team-lab
./deploy/build-local.sh

# 2. Import blueprint via API
export CYROID_TOKEN=your-jwt-token
curl -X POST "http://localhost/api/v1/blueprints/import" \
  -H "Authorization: Bearer $CYROID_TOKEN" \
  -F "file=@../../red-team-training-lab.blueprint.zip"
```

### Option 3: Fresh CYROID Installation

Clone and run everything:

```bash
# Start CYROID
docker compose up -d

# Build lab images
cd scenarios/red-team-lab/deploy
./build-images.sh build

# Import to local CYROID
export CYROID_API_URL=http://localhost:8000/api
# Login via UI first, then get token
python import-to-cyroid.py
```

## Components

### Vulnerable WordPress (`containers/wordpress/`)

- Ubuntu 22.04 with Apache, PHP, MySQL
- Acme Employee Portal plugin with:
  - SQL Injection in search parameter
  - SQL Injection in employee_id parameter
  - Stored XSS in notes field
- SSH enabled with password auth (credential reuse)
- `secrets` database accessible via SQLi

### File Server (`containers/fileserver/`)

- Samba with multiple shares
- Sensitive data: `secret-formula.txt`, `employee-ssn.csv`, `passwords.txt`
- User accounts match AD credentials

### Workstation (`containers/workstation/`)

- Headless Firefox with Selenium
- Auto-browses WordPress every 60 seconds
- Triggers BeEF hooks when attacker injects XSS

### Domain Controller (Windows or Samba)

**Windows DC** (`containers/windows-dc/`) - Used on Linux with KVM:
- Windows Server 2019 setup scripts
- Creates `acmewidgets.local` domain
- **Misconfiguration**: `svc_backup` has DCSync rights
- Weak, reused passwords

**Samba AD DC** (`containers/samba-dc/`) - Used on macOS or Linux without KVM:
- Ubuntu 22.04 with Samba 4 AD DC
- Creates identical `acmewidgets.local` domain
- Same users, passwords, and DCSync misconfiguration
- Fully compatible with Impacket tools (secretsdump, psexec, etc.)

## Credentials

All credentials are intentionally weak and reused across systems:

| System | Username | Password | Notes |
|--------|----------|----------|-------|
| WordPress | admin | Acme2024! | Also SSH password |
| WordPress | jsmith | Summer2024 | Also VPN/AD |
| WordPress | mwilliams | Welcome123 | Also VPN/AD |
| MySQL | wp_user | Acme2024! | Can read secrets DB |
| RouterOS | admin | Mikr0t1k! | Router admin |
| RouterOS | backup | backup123 | Weak for brute force |
| AD | Administrator | Adm1n2024! | Domain admin |
| AD | svc_backup | Backup2024! | Has DCSync rights |

## Student Objectives

1. **Domain Dominance**: Submit `krbtgt` or `Administrator` NTLM hash
2. **Data Exfiltration**: Retrieve `secret-formula.txt` contents
3. **Ransomware Demo**: Place ransom note on file server

## Directory Structure

```
red-team-training-lab/
├── red-team-training-lab.blueprint.zip  # ← IMPORT THIS INTO CYROID
├── setup.sh                             # Full automated setup
├── cleanup.sh                           # Clean up deployment
└── scenarios/red-team-lab/
    ├── README.md               # This file
    ├── range-blueprint.yml     # Full range definition
    ├── configs/
    │   └── credentials.yml     # All lab credentials
    ├── containers/
    │   ├── wordpress/          # SQLi/XSS target
    │   ├── fileserver/         # Sensitive data
    │   ├── workstation/        # BeEF victim
    │   ├── windows-dc/         # Windows DC setup (Linux+KVM)
    │   └── samba-dc/           # Samba AD DC (macOS/Linux)
    ├── plugins/
    │   └── acme-employee-portal/  # Vulnerable WP plugin
    └── deploy/
        ├── build-local.sh      # Build container images
        ├── import-to-cyroid.py # Import script (advanced)
        └── build-images.sh     # Build & push to registry
```

## Customization

### Change Credentials

Edit `configs/credentials.yml` and update:
- `containers/wordpress/mysql-init.sql`
- `containers/wordpress/setup.sh`
- `containers/fileserver/entrypoint.sh`
- `containers/windows-dc/oem/create-users.ps1`

### Add New Attack Paths

1. Create new container in `containers/`
2. Add template to `deploy/import-to-cyroid.py`
3. Update `range-blueprint.yml`
4. Rebuild and reimport

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `USE_SAMBA_DC` | `false` | Set to `true` to use Samba AD DC on Linux (even with KVM) |
| `DC_TYPE` | auto | Override DC type: `windows` or `samba` |
| `NUM_STUDENTS` | 1 | Number of student environments to create |
| `CYROID_VERSION` | latest | CYROID version to install |

Example: Fast setup on Linux with Samba DC:
```bash
USE_SAMBA_DC=true ./setup.sh
```

## For Instructors

### Scaling for Multiple Students

Each student should get their own range instance. CYROID handles this automatically:

```bash
# Create student ranges
for i in $(seq 1 10); do
    python import-to-cyroid.py --range-name "Red Team Lab - Student $i"
done
```

### Monitoring Progress

- Use CYROID event logs to track student activity
- Check VM console access patterns
- Review network traffic between VMs

### Resetting Environments

From CYROID UI:
1. Stop range
2. Delete range
3. Reimport from templates

## License

For educational purposes only. Do not deploy on production networks.
