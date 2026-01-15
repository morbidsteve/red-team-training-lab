#!/bin/bash

create_smb_user() {
    local user=$1
    local pass=$2
    useradd -M -s /sbin/nologin "$user" 2>/dev/null || true
    echo -e "$pass\n$pass" | smbpasswd -a -s "$user"
}

# Create users matching AD credentials
create_smb_user "admin" "Acme2024!"
create_smb_user "jsmith" "Summer2024"
create_smb_user "mwilliams" "Welcome123"
create_smb_user "svc_backup" "Backup2024!"

exec smbd --foreground --no-process-group
