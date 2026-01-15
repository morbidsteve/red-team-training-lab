#!/bin/bash
set -e

# Start MySQL
service mysql start

# Wait for MySQL
until mysqladmin ping -h localhost --silent; do
    sleep 1
done

# Fix MySQL socket permissions for Apache/PHP access
# The mysqld directory is created with 700 permissions by default,
# which prevents www-data from accessing the socket
chmod 755 /var/run/mysqld/

# Initialize database
mysql < /mysql-init.sql

# Start SSH
service ssh start

# Install WP-CLI
if [ ! -f /usr/local/bin/wp ]; then
    curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp
fi

# Install WordPress if not done
if ! wp core is-installed --path=/var/www/html --allow-root 2>/dev/null; then
    wp core install \
        --path=/var/www/html \
        --url="http://$(hostname -I | awk '{print $1}')" \
        --title="Acme Widgets Inc." \
        --admin_user="admin" \
        --admin_password="Acme2024!" \
        --admin_email="admin@acmewidgets.local" \
        --allow-root

    # Create users
    wp user create jsmith jsmith@acmewidgets.local \
        --role=editor --user_pass="Summer2024" \
        --path=/var/www/html --allow-root

    wp user create mwilliams mwilliams@acmewidgets.local \
        --role=author --user_pass="Welcome123" \
        --path=/var/www/html --allow-root

    # Activate plugin
    wp plugin activate acme-employee-portal --path=/var/www/html --allow-root

    # Create employee directory page
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
