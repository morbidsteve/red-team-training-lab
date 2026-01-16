#!/bin/bash
set -e

# Domain configuration (can be overridden via environment variables)
REALM="${SAMBA_REALM:-ACMEWIDGETS.LOCAL}"
DOMAIN="${SAMBA_DOMAIN:-ACME}"
ADMIN_PASS="${SAMBA_ADMIN_PASS:-Adm1n2024!}"

# Check if domain is already provisioned
if [ ! -f /var/lib/samba/private/sam.ldb ]; then
    echo "=== First run: Provisioning Samba AD DC ==="
    /usr/local/bin/provision-domain.sh "$REALM" "$DOMAIN" "$ADMIN_PASS"
else
    echo "=== Domain already provisioned, starting services ==="
fi

# Update /etc/hosts for the domain
HOSTNAME=$(hostname)
IP=$(hostname -I | awk '{print $1}')
echo "$IP ${HOSTNAME}.${REALM,,} ${HOSTNAME}" >> /etc/hosts

# Start Samba AD DC in foreground
echo "=== Starting Samba AD DC ==="
exec samba --foreground --no-process-group
