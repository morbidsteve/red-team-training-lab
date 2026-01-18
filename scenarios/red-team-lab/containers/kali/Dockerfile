FROM kasmweb/kali-rolling-desktop:1.14.0

USER root

# Fix Kali GPG key and update repos
RUN wget -q -O - https://archive.kali.org/archive-key.asc | apt-key add - && \
    apt-get update

# Install passlib for proper crypt compatibility (Python 3.13 removed crypt module)
RUN apt-get install -y python3-passlib

# Create crypt.py shim using passlib (KasmVNC startup needs it)
RUN printf '%s\n' \
    'from passlib.hash import sha256_crypt' \
    'def crypt(word, salt=None):' \
    '    if salt is None:' \
    '        return sha256_crypt.hash(word)' \
    '    return sha256_crypt.using(salt=salt.split("$")[2] if "$" in salt else salt[:16]).hash(word)' \
    > /usr/lib/python3/dist-packages/crypt.py

# Install Kali metapackages and common red team tools
RUN apt-get install -y --no-install-recommends \
    # Web enumeration
    gobuster \
    dirb \
    nikto \
    whatweb \
    # SQL injection
    sqlmap \
    # Brute force
    hydra \
    medusa \
    # SMB/AD tools
    smbclient \
    smbmap \
    crackmapexec \
    evil-winrm \
    # Impacket suite (secretsdump, psexec, etc.)
    python3-impacket \
    impacket-scripts \
    # Browser exploitation
    beef-xss \
    # Network tools
    nmap \
    netcat-openbsd \
    tcpdump \
    wireshark \
    # Password cracking
    john \
    hashcat \
    # Wordlists
    wordlists \
    seclists \
    # Misc utilities
    curl \
    wget \
    vim \
    git \
    jq \
    tree \
    # Metasploit (large but useful)
    metasploit-framework \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Extract rockyou wordlist
RUN gunzip -k /usr/share/wordlists/rockyou.txt.gz 2>/dev/null || true

# Create convenient symlinks
RUN ln -sf /usr/share/wordlists /wordlists 2>/dev/null || true && \
    ln -sf /usr/share/seclists /seclists 2>/dev/null || true

# Disable VNC authentication (CYROID handles access control)
# Replace password hash variables with empty strings and write empty passwords to file
# This must be AFTER tool installation to preserve Docker layer cache for faster iteration
RUN sed -i 's|VNC_PW_HASH=.*|VNC_PW_HASH=""|' /dockerstartup/vnc_startup.sh && \
    sed -i 's|VNC_VIEW_PW_HASH=.*|VNC_VIEW_PW_HASH=""|' /dockerstartup/vnc_startup.sh && \
    sed -i 's|echo "kasm_user:\${VNC_PW_HASH}:ow"|echo "kasm_user::ow"|' /dockerstartup/vnc_startup.sh && \
    sed -i 's|echo "kasm_viewer:\${VNC_VIEW_PW_HASH}:"|echo "kasm_viewer::"|' /dockerstartup/vnc_startup.sh

USER 1000
