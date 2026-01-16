# Samba 4 Active Directory Domain Controller for Red Team Training Lab
# Provides equivalent functionality to Windows DC for DCSync, Pass-the-Hash, etc.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install Samba AD DC and dependencies
# Note: samba package includes AD DC functionality in Ubuntu 22.04
RUN apt-get update && apt-get install -y \
    samba \
    samba-dsdb-modules \
    samba-vfs-modules \
    krb5-user \
    krb5-kdc \
    winbind \
    libnss-winbind \
    libpam-winbind \
    dnsutils \
    ldap-utils \
    ldb-tools \
    acl \
    attr \
    python3 \
    python3-samba \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Remove default smb.conf (samba-tool provision will create a new one)
RUN rm -f /etc/samba/smb.conf

# Copy provisioning scripts
COPY provision-domain.sh /usr/local/bin/provision-domain.sh
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /usr/local/bin/provision-domain.sh /entrypoint.sh

# Samba AD DC ports
# 53: DNS
# 88: Kerberos
# 135: RPC Endpoint Mapper
# 139: NetBIOS Session
# 389: LDAP
# 445: SMB
# 464: Kerberos kpasswd
# 636: LDAPS
# 3268: Global Catalog
# 3269: Global Catalog SSL
EXPOSE 53 53/udp 88 88/udp 135 139 389 389/udp 445 464 464/udp 636 3268 3269

# Data volume for Samba databases
VOLUME ["/var/lib/samba", "/var/log/samba"]

ENTRYPOINT ["/entrypoint.sh"]
