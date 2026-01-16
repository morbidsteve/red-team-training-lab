# Cross-Platform Domain Controller Design

## Overview

Enable the Red Team Training Lab to run on both macOS and Linux by providing a Samba 4 AD DC container as an alternative to the Windows Server 2019 DC. The system auto-detects the platform and selects the appropriate DC implementation.

## Problem

The Windows Server 2019 DC requires KVM for acceptable performance. macOS doesn't support KVM, making the lab impractical to run on Mac. Linux systems without KVM also suffer from extremely slow Windows VM performance.

## Solution

Create a Samba 4 AD DC container that provides equivalent functionality for all attack scenarios (DCSync, Pass-the-Hash, BloodHound enumeration). Auto-detect the platform and KVM availability to choose the right DC implementation.

## Detection Logic

```
1. Detect OS (darwin = Mac, linux = Linux)
2. If Linux, check for /dev/kvm
3. Determine DC type:
   - Mac → Samba DC (automatic)
   - Linux without KVM → Samba DC (automatic)
   - Linux with KVM + USE_SAMBA_DC=true → Samba DC
   - Linux with KVM (default) → Windows DC
4. Export DC_TYPE to import script
```

**User messaging:**
- Mac: "Detected macOS - using Samba AD DC (Windows DC requires KVM)"
- Linux no KVM: "KVM not available - using Samba AD DC"
- Linux + env var: "USE_SAMBA_DC=true - using Samba AD DC"
- Linux default: "Using Windows DC (set USE_SAMBA_DC=true for faster Samba alternative)"

## Samba DC Container

**Directory:** `scenarios/red-team-lab/containers/samba-dc/`

**Files:**
- `Dockerfile` - Ubuntu 22.04 + Samba 4 AD DC packages
- `provision-domain.sh` - Creates domain, users, misconfigurations
- `smb.conf` - Samba AD DC configuration template

**Dockerfile approach:**
```dockerfile
FROM ubuntu:22.04
# Install: samba, samba-ad-dc, krb5-user, winbind
# Copy provision script
# ENTRYPOINT runs provision on first boot, then starts samba
```

**provision-domain.sh responsibilities:**
1. Run `samba-tool domain provision`:
   - Realm: ACMEWIDGETS.LOCAL
   - Domain: ACME
   - Admin password: Adm1n2024!
2. Create users with matching passwords:
   - jsmith / Summer2024 (Domain Users, IT Support)
   - mwilliams / Welcome123 (Domain Users, Accounting)
   - svc_backup / Backup2024! (Domain Users, Backup Operators)
3. Apply DCSync rights to svc_backup via `samba-tool dsacl`
4. Start Samba services

**Container specs:**
- IP: 172.16.2.10 (same as Windows DC)
- Hostname: DC01
- Resources: 2 CPU, 2GB RAM

## Import Script Changes

**File:** `scenarios/red-team-lab/deploy/import-to-cyroid.py`

Accept `DC_TYPE` environment variable. When loading `range-blueprint.yml`:

**If DC_TYPE == "samba":**
- Change `type: vm` → `type: container`
- Change image to `red-team-lab/samba-dc:latest`
- Remove Windows-specific fields (iso, disk_size)
- Reduce resources (2 CPU, 2GB RAM)
- Keep same IP (172.16.2.10) and network

**If DC_TYPE == "windows":**
- No changes, use existing definition

## Build Script Changes

**File:** `scenarios/red-team-lab/deploy/build-images.sh`

Add `samba-dc` to container list:
```bash
CONTAINERS="wordpress fileserver workstation samba-dc"
```

Always build Samba DC image regardless of OS.

## Files to Create

- `scenarios/red-team-lab/containers/samba-dc/Dockerfile`
- `scenarios/red-team-lab/containers/samba-dc/provision-domain.sh`
- `scenarios/red-team-lab/containers/samba-dc/smb.conf`

## Files to Modify

- `setup.sh` - OS/KVM detection, DC_TYPE logic, messaging
- `scenarios/red-team-lab/deploy/import-to-cyroid.py` - DC_TYPE handling
- `scenarios/red-team-lab/deploy/build-images.sh` - Add samba-dc to build

## Attack Chain Verification

After implementation, verify on Mac:
1. Samba DC starts and creates domain
2. DCSync attack: `impacket-secretsdump 'acmewidgets.local/svc_backup:Backup2024!@172.16.2.10'`
3. BloodHound: `bloodhound-python -u svc_backup -p 'Backup2024!' -d acmewidgets.local -ns 172.16.2.10`
4. Pass-the-hash with extracted Administrator NTLM hash

## Documentation Updates

- Update README with Mac compatibility
- Document `USE_SAMBA_DC=true` option for Linux users
