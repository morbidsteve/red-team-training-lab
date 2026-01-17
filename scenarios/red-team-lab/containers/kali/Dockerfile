FROM kasmweb/kali-rolling-desktop:1.14.0

USER root

# Fix Kali GPG key and update repos
RUN wget -q -O - https://archive.kali.org/archive-key.asc | apt-key add - && \
    apt-get update

# Fix Python crypt module (removed in Python 3.13, needed by KasmVNC)
# Create a minimal crypt.py using only standard library
RUN mkdir -p /usr/lib/python3/dist-packages && \
    printf '%s\n' \
    '"""Compatibility shim for removed crypt module (Python 3.13+)"""' \
    'import hashlib' \
    'import os' \
    'def crypt(word, salt=None):' \
    '    if salt is None:' \
    '        salt = "$5$" + os.urandom(8).hex() + "$"' \
    '    if "$5$" in str(salt):' \
    '        parts = str(salt).split("$")' \
    '        actual_salt = parts[2][:16] if len(parts) >= 3 else str(salt)[:16]' \
    '        h = hashlib.sha256((actual_salt + word).encode()).hexdigest()' \
    '        return "$5$" + actual_salt + "$" + h' \
    '    h = hashlib.sha256((str(salt)[:8] + word).encode()).hexdigest()' \
    '    return "$5$" + str(salt)[:8] + "$" + h' \
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

USER 1000
