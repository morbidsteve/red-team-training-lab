#!/usr/bin/env python3
"""
Import Red Team Training Lab into an existing CYROID installation.

Usage:
    # Set your CYROID API URL and get an auth token first
    export CYROID_API_URL=https://your-cyroid-instance.com/api
    export CYROID_TOKEN=your-jwt-token

    # Run the import
    python import-to-cyroid.py

    # Or specify URL directly
    python import-to-cyroid.py --api-url http://localhost:8000/api --token YOUR_TOKEN
"""

import os
import sys
import json
import argparse
import requests
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
SCENARIOS_DIR = SCRIPT_DIR.parent

# Template definitions for the Red Team Lab
# Use get_templates(local=True/False) to get appropriate image names

def get_templates(local=False, registry="ghcr.io/your-org"):
    """Get template definitions with appropriate image paths."""

    if local:
        wordpress_image = "redteam-lab-wordpress:latest"
        fileserver_image = "redteam-lab-fileserver:latest"
        workstation_image = "redteam-lab-workstation:latest"
    else:
        wordpress_image = f"{registry}/redteam-lab-wordpress:latest"
        fileserver_image = f"{registry}/redteam-lab-fileserver:latest"
        workstation_image = f"{registry}/redteam-lab-workstation:latest"

    return [
        {
            "name": "Red Team - Kali Attack Box",
            "description": "Kali Linux with pre-installed penetration testing tools",
            "os_type": "linux",
            "os_variant": "Kali Linux",
            "vm_type": "container",
            "base_image": "kalilinux/kali-rolling:latest",
            "default_cpu": 4,
            "default_ram_mb": 4096,
            "default_disk_gb": 60,
            "tags": ["red-team", "attacker", "kali"],
            "config_script": "apt-get update && apt-get install -y kali-linux-headless"
        },
        {
            "name": "Red Team - WordPress Target",
            "description": "WordPress with vulnerable Acme Employee Portal plugin (SQLi/XSS)",
            "os_type": "linux",
            "os_variant": "Ubuntu 22.04",
            "vm_type": "container",
            "base_image": wordpress_image,
            "default_cpu": 2,
            "default_ram_mb": 2048,
            "default_disk_gb": 20,
            "tags": ["red-team", "victim", "sqli", "xss", "wordpress"],
            "config_script": "# WordPress auto-configures on startup"
        },
        {
            "name": "Red Team - File Server",
            "description": "Samba file server with sensitive business data",
            "os_type": "linux",
            "os_variant": "Ubuntu 22.04",
            "vm_type": "container",
            "base_image": fileserver_image,
            "default_cpu": 1,
            "default_ram_mb": 1024,
            "default_disk_gb": 10,
            "tags": ["red-team", "victim", "samba", "exfil-target"]
        },
        {
            "name": "Red Team - Victim Workstation",
            "description": "Simulated employee workstation (BeEF hook target)",
            "os_type": "linux",
            "os_variant": "Ubuntu 22.04",
            "vm_type": "container",
            "base_image": workstation_image,
            "default_cpu": 1,
            "default_ram_mb": 1024,
            "default_disk_gb": 10,
            "tags": ["red-team", "victim", "workstation", "beef-target"]
        },
        {
            "name": "Red Team - Windows DC",
            "description": "Windows Server 2019 Domain Controller with misconfigurations",
            "os_type": "windows",
            "os_variant": "Windows Server 2019",
            "vm_type": "windows_vm",
            "base_image": "2019",
            "default_cpu": 4,
            "default_ram_mb": 4096,
            "default_disk_gb": 80,
            "tags": ["red-team", "victim", "windows", "dc", "ad"],
            "config_script": "# See scenarios/red-team-lab/containers/windows-dc/oem/ for setup scripts"
        },
        {
            "name": "Red Team - Redirector",
            "description": "Lightweight Alpine redirector for C2 traffic",
            "os_type": "linux",
            "os_variant": "Alpine 3.19",
            "vm_type": "container",
            "base_image": "alpine:3.19",
            "default_cpu": 1,
            "default_ram_mb": 512,
            "default_disk_gb": 10,
            "tags": ["red-team", "attacker", "redirector"],
            "config_script": "apk add --no-cache socat iptables && echo 1 > /proc/sys/net/ipv4/ip_forward"
        }
    ]

# Default templates for backward compatibility
TEMPLATES = get_templates(local=False)

def get_range_blueprint(subnet_offset: int = 0):
    """
    Get range blueprint with subnet offset for multiple student deployments.
    subnet_offset: Adds to second octet (e.g., 0 -> 172.16.x.x, 1 -> 172.17.x.x)
    """
    base = 16 + subnet_offset
    return {
        "name": "Red Team Training Lab",
        "description": "Attack training environment: SQLi, SSH brute force, BeEF exploitation, AD attack",
        "networks": [
            {"name": "internet", "subnet": f"172.{base}.0.0/24", "gateway": f"172.{base}.0.1", "internal": False},
            {"name": "dmz", "subnet": f"172.{base}.1.0/24", "gateway": f"172.{base}.1.1", "internal": True},
            {"name": "internal", "subnet": f"172.{base}.2.0/24", "gateway": f"172.{base}.2.1", "internal": True}
        ],
        "vms": [
            {"template": "Red Team - Kali Attack Box", "hostname": "kali", "network": "internet", "ip": f"172.{base}.0.10"},
            {"template": "Red Team - Redirector", "hostname": "redir1", "network": "internet", "ip": f"172.{base}.0.20"},
            {"template": "Red Team - Redirector", "hostname": "redir2", "network": "internet", "ip": f"172.{base}.0.21"},
            {"template": "Red Team - WordPress Target", "hostname": "webserver", "network": "dmz", "ip": f"172.{base}.1.10"},
            {"template": "Red Team - Windows DC", "hostname": "WIN-DC01", "network": "internal", "ip": f"172.{base}.2.10"},
            {"template": "Red Team - File Server", "hostname": "fileserver", "network": "internal", "ip": f"172.{base}.2.20"},
            {"template": "Red Team - Victim Workstation", "hostname": "ws01", "network": "internal", "ip": f"172.{base}.2.30"}
        ]
    }

# Default blueprint for backward compatibility
RANGE_BLUEPRINT = get_range_blueprint(0)


class CyroidImporter:
    def __init__(self, api_url: str, token: str):
        self.api_url = api_url.rstrip('/')
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }

    def check_connection(self) -> bool:
        """Verify connection to CYROID API."""
        try:
            resp = requests.get(f"{self.api_url}/auth/me", headers=self.headers)
            if resp.status_code == 200:
                user = resp.json()
                print(f"Connected as: {user.get('username', 'unknown')}")
                return True
            else:
                print(f"Auth failed: {resp.status_code}")
                return False
        except Exception as e:
            print(f"Connection error: {e}")
            return False

    def get_existing_templates(self) -> dict:
        """Get existing templates by name."""
        resp = requests.get(f"{self.api_url}/templates", headers=self.headers)
        if resp.status_code == 200:
            return {t['name']: t for t in resp.json()}
        return {}

    def create_template(self, template: dict) -> dict:
        """Create a VM template."""
        resp = requests.post(
            f"{self.api_url}/templates",
            headers=self.headers,
            json=template
        )
        if resp.status_code in (200, 201):
            return resp.json()
        else:
            print(f"  Failed to create template: {resp.status_code} - {resp.text}")
            return None

    def create_range(self, name: str, description: str) -> dict:
        """Create a new range."""
        resp = requests.post(
            f"{self.api_url}/ranges",
            headers=self.headers,
            json={"name": name, "description": description}
        )
        if resp.status_code in (200, 201):
            return resp.json()
        else:
            print(f"  Failed to create range: {resp.status_code} - {resp.text}")
            return None

    def create_network(self, range_id: str, network: dict) -> dict:
        """Create a network in a range."""
        network_data = {
            "range_id": range_id,
            "name": network["name"],
            "subnet": network["subnet"],
            "gateway": network["gateway"],
            "isolation_level": "open" if not network.get("internal", True) else "controlled"
        }
        resp = requests.post(
            f"{self.api_url}/networks",
            headers=self.headers,
            json=network_data
        )
        if resp.status_code in (200, 201):
            return resp.json()
        else:
            print(f"    Failed to create network: {resp.status_code} - {resp.text}")
        return None

    def create_vm(self, range_id: str, vm: dict) -> dict:
        """Create a VM in a range."""
        vm_data = {
            "range_id": range_id,
            **vm
        }
        resp = requests.post(
            f"{self.api_url}/vms",
            headers=self.headers,
            json=vm_data
        )
        if resp.status_code in (200, 201):
            return resp.json()
        else:
            print(f"    Failed to create VM: {resp.status_code} - {resp.text}")
        return None

    def import_templates(self, templates: list) -> tuple:
        """Import all Red Team Lab templates. Returns (id_map, details_map)."""
        print("\n=== Importing Templates ===")
        existing = self.get_existing_templates()
        template_map = {}  # name -> id
        template_details = {}  # name -> full template dict

        for template in templates:
            name = template['name']
            if name in existing:
                print(f"  [SKIP] {name} (already exists)")
                template_map[name] = existing[name]['id']
                template_details[name] = existing[name]
            else:
                print(f"  [CREATE] {name}")
                result = self.create_template(template)
                if result:
                    template_map[name] = result['id']
                    template_details[name] = result
                    print(f"    Created: {result['id']}")

        return template_map, template_details

    def import_range(self, template_map: dict, template_details: dict, range_name: str = None, subnet_offset: int = 0) -> str:
        """Import the range blueprint."""
        print("\n=== Creating Range ===")

        blueprint = get_range_blueprint(subnet_offset)
        name = range_name or blueprint['name']
        description = blueprint['description']

        range_obj = self.create_range(name, description)
        if not range_obj:
            print("Failed to create range")
            return None

        range_id = range_obj['id']
        print(f"  Created range: {name} ({range_id})")

        # Create networks
        print("\n=== Creating Networks ===")
        network_map = {}
        for net in blueprint['networks']:
            print(f"  [CREATE] {net['name']} ({net['subnet']})")
            result = self.create_network(range_id, net)
            if result:
                network_map[net['name']] = result['id']

        # Create VMs
        print("\n=== Creating VMs ===")
        for vm in blueprint['vms']:
            template_name = vm['template']
            template_id = template_map.get(template_name)
            template = template_details.get(template_name, {})
            network_id = network_map.get(vm['network'])

            if not template_id:
                print(f"  [SKIP] {vm['hostname']} - template not found: {template_name}")
                continue

            if not network_id:
                print(f"  [SKIP] {vm['hostname']} - network not found: {vm['network']}")
                continue

            vm_data = {
                "hostname": vm['hostname'],
                "template_id": template_id,
                "network_id": network_id,
                "ip_address": vm['ip'],
                "cpu": template.get('default_cpu', 2),
                "ram_mb": template.get('default_ram_mb', 2048),
                "disk_gb": template.get('default_disk_gb', 20)
            }

            print(f"  [CREATE] {vm['hostname']} ({vm['ip']})")
            self.create_vm(range_id, vm_data)

        return range_id


def main():
    parser = argparse.ArgumentParser(description="Import Red Team Lab into CYROID")
    parser.add_argument("--api-url", default=os.environ.get("CYROID_API_URL", "http://localhost:8000/api"))
    parser.add_argument("--token", default=os.environ.get("CYROID_TOKEN"))
    parser.add_argument("--range-name", help="Custom name for the range")
    parser.add_argument("--templates-only", action="store_true", help="Only import templates, don't create range")
    parser.add_argument("--local", action="store_true", help="Use local Docker images (no registry)")
    parser.add_argument("--registry", default="ghcr.io/your-org", help="Container registry (ignored if --local)")
    parser.add_argument("--subnet-offset", type=int, default=0, help="Subnet offset for multiple ranges (0=172.16.x, 1=172.17.x, etc)")
    parser.add_argument("--export-json", help="Export templates/range as JSON file instead of importing")

    args = parser.parse_args()

    # Get templates with appropriate image paths
    templates = get_templates(local=args.local, registry=args.registry)

    # Export mode
    if args.export_json:
        export_data = {
            "templates": templates,
            "range": RANGE_BLUEPRINT
        }
        with open(args.export_json, 'w') as f:
            json.dump(export_data, f, indent=2)
        print(f"Exported to {args.export_json}")
        return

    # Import mode
    if not args.token:
        print("Error: CYROID_TOKEN not set")
        print("Get a token by logging into CYROID, then:")
        print("  export CYROID_TOKEN=your-jwt-token")
        sys.exit(1)

    importer = CyroidImporter(args.api_url, args.token)

    print(f"CYROID API: {args.api_url}")
    if args.local:
        print("Using LOCAL Docker images (no registry)")
    if not importer.check_connection():
        sys.exit(1)

    # Import templates
    template_map, template_details = importer.import_templates(templates)

    # Create range (unless templates-only)
    if not args.templates_only:
        range_id = importer.import_range(template_map, template_details, args.range_name, args.subnet_offset)
        if range_id:
            print(f"\n=== Import Complete ===")
            print(f"Range ID: {range_id}")
            print(f"View in CYROID UI to deploy!")
    else:
        print("\n=== Templates Imported ===")
        print("Use CYROID UI to create ranges from these templates")


if __name__ == "__main__":
    main()
