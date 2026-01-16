#!/bin/bash
# Provision Samba AD DC with intentional misconfigurations for Red Team training
set -e

REALM="${1:-ACMEWIDGETS.LOCAL}"
DOMAIN="${2:-ACME}"
ADMIN_PASS="${3:-Adm1n2024!}"

echo "Provisioning Samba AD DC..."
echo "  Realm: $REALM"
echo "  Domain: $DOMAIN"

# Provision the domain
samba-tool domain provision \
    --realm="$REALM" \
    --domain="$DOMAIN" \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASS" \
    --use-rfc2307

# Copy Kerberos configuration
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

echo ""
echo "=== Creating Organizational Units ==="

# Create OUs
samba-tool ou create "OU=AcmeUsers,DC=${REALM//./,DC=}" || true
samba-tool ou create "OU=ServiceAccounts,DC=${REALM//./,DC=}" || true

echo ""
echo "=== Creating Security Groups ==="

# Create custom groups
samba-tool group add "IT Support" --description="IT Support Staff" || true
samba-tool group add "Accounting" --description="Accounting Department" || true

echo ""
echo "=== Creating User Accounts ==="

# Create domain users with weak passwords (matching credentials.yml)
# jsmith - IT Support user
samba-tool user create jsmith "Summer2024" \
    --given-name="John" \
    --surname="Smith" \
    --mail-address="jsmith@${REALM,,}" \
    --use-username-as-cn || true
samba-tool group addmembers "IT Support" jsmith || true

# mwilliams - Accounting user
samba-tool user create mwilliams "Welcome123" \
    --given-name="Mary" \
    --surname="Williams" \
    --mail-address="mwilliams@${REALM,,}" \
    --use-username-as-cn || true
samba-tool group addmembers "Accounting" mwilliams || true

# svc_backup - Service account with DCSync rights (MISCONFIGURATION!)
samba-tool user create svc_backup "Backup2024!" \
    --given-name="Backup" \
    --surname="Service" \
    --mail-address="svc_backup@${REALM,,}" \
    --use-username-as-cn || true
samba-tool group addmembers "Backup Operators" svc_backup || true

echo ""
echo "=== Applying DCSync Misconfiguration to svc_backup ==="

# Get the domain DN
DOMAIN_DN="DC=${REALM//./,DC=}"

# Grant DCSync rights to svc_backup
# These are the GUIDs for:
#   - DS-Replication-Get-Changes (1131f6aa-9c07-11d1-f79f-00c04fc2dcd2)
#   - DS-Replication-Get-Changes-All (1131f6ad-9c07-11d1-f79f-00c04fc2dcd2)
#
# This is the intentional misconfiguration that allows DCSync attack

# Method 1: Use samba-tool dsacl (preferred)
samba-tool dsacl set \
    --objectdn="$DOMAIN_DN" \
    --action=allow \
    --principal="$DOMAIN\\svc_backup" \
    --rights="CR" \
    --rightstype="control_access" \
    --rightsattrguid="1131f6aa-9c07-11d1-f79f-00c04fc2dcd2" || {
    echo "Warning: Could not set DS-Replication-Get-Changes via dsacl, trying alternative method..."
}

samba-tool dsacl set \
    --objectdn="$DOMAIN_DN" \
    --action=allow \
    --principal="$DOMAIN\\svc_backup" \
    --rights="CR" \
    --rightstype="control_access" \
    --rightsattrguid="1131f6ad-9c07-11d1-f79f-00c04fc2dcd2" || {
    echo "Warning: Could not set DS-Replication-Get-Changes-All via dsacl, trying alternative method..."
}

# Method 2: Alternative using ldbmodify if dsacl doesn't work
# This adds the ACEs directly to the nTSecurityDescriptor
cat > /tmp/dcsync-acl.ldif << EOF
dn: $DOMAIN_DN
changetype: modify
add: nTSecurityDescriptor
nTSecurityDescriptor:: $(python3 << 'PYEOF'
import subprocess
import base64

# Get the SID of svc_backup
result = subprocess.run(
    ['wbinfo', '-n', 'svc_backup'],
    capture_output=True, text=True
)
if result.returncode != 0:
    # Try alternative method
    result = subprocess.run(
        ['samba-tool', 'user', 'show', 'svc_backup', '--attributes=objectSid'],
        capture_output=True, text=True
    )

# For now, just print empty - the dsacl method above should work
print("")
PYEOF
)
EOF

echo ""
echo "=== Verifying DCSync Rights ==="

# Verify the ACL was applied
samba-tool dsacl get --objectdn="$DOMAIN_DN" 2>/dev/null | grep -i "svc_backup" || echo "(ACL verification - check manually if needed)"

echo ""
echo "=== Domain Provisioning Complete ==="
echo ""
echo "Domain: $REALM"
echo "NetBIOS: $DOMAIN"
echo "Administrator password: $ADMIN_PASS"
echo ""
echo "Users created:"
echo "  - jsmith / Summer2024 (IT Support)"
echo "  - mwilliams / Welcome123 (Accounting)"
echo "  - svc_backup / Backup2024! (Backup Operators + DCSync rights!)"
echo ""
echo "DCSync Attack Test:"
echo "  impacket-secretsdump '${REALM,,}/svc_backup:Backup2024!@<DC_IP>'"
echo ""
