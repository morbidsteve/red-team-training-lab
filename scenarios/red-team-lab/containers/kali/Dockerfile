# OPTIONAL: Custom Kali Linux Attack Box with additional tools
#
# By default, the lab uses kasmweb/kali-rolling-desktop:1.14.0 directly.
# This Dockerfile is provided for customization if you want to pre-install
# additional tools instead of installing them at runtime.
#
# To use this custom image:
#   1. Build: docker build -t kasmweb/redteam-lab-kali:latest .
#   2. Update template base_image to: kasmweb/redteam-lab-kali:latest

FROM kasmweb/kali-rolling-desktop:1.14.0

USER root

# Install additional red team tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Reconnaissance
    nmap \
    masscan \
    gobuster \
    dirb \
    nikto \
    whatweb \
    dnsrecon \
    enum4linux \
    # Web exploitation
    sqlmap \
    burpsuite \
    # Network tools
    netcat-traditional \
    proxychains4 \
    smbclient \
    impacket-scripts \
    crackmapexec \
    # Exploitation frameworks
    metasploit-framework \
    beef-xss \
    # Password attacks
    hydra \
    john \
    hashcat \
    wordlists \
    seclists \
    # Post-exploitation
    bloodhound \
    # Utilities
    python3-pip \
    git \
    curl \
    wget \
    vim \
    tmux \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install additional Python tools
RUN pip3 install --break-system-packages \
    impacket \
    bloodhound \
    crackmapexec \
    pwntools

# Pre-configure some tools
RUN mkdir -p /home/kasm-user/tools && \
    chown -R kasm-user:kasm-user /home/kasm-user/tools

# Copy startup script for tool initialization
COPY --chown=kasm-user:kasm-user startup.sh /home/kasm-user/startup.sh
RUN chmod +x /home/kasm-user/startup.sh

# Set environment variables
ENV HOME=/home/kasm-user
ENV SHELL=/bin/bash

USER kasm-user

# Run custom startup on container start
RUN echo '/home/kasm-user/startup.sh &' >> /home/kasm-user/.bashrc

WORKDIR /home/kasm-user
