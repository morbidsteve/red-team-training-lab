#!/bin/bash

# Start virtual display
export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 &
sleep 2

# Wait for WordPress
echo "[*] Waiting for WordPress..."
until curl -s "${WORDPRESS_URL:-http://wordpress}" > /dev/null 2>&1; do
    sleep 5
done
echo "[*] WordPress is up!"

exec python3 /browse-script.py
