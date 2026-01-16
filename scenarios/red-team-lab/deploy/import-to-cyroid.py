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

def get_templates(local=False, registry="ghcr.io/your-org", dc_type="windows"):
    """Get template definitions with appropriate image paths.

    Args:
        local: If True, use local Docker image names without registry prefix
        registry: Container registry for remote deployments
        dc_type: "windows" for Windows DC (requires KVM) or "samba" for Samba AD DC (Linux-based)
    """

    if local:
        wordpress_image = "redteam-lab-wordpress:latest"
        fileserver_image = "redteam-lab-fileserver:latest"
        workstation_image = "redteam-lab-workstation:latest"
        samba_dc_image = "redteam-lab-samba-dc:latest"
    else:
        wordpress_image = f"{registry}/redteam-lab-wordpress:latest"
        fileserver_image = f"{registry}/redteam-lab-fileserver:latest"
        workstation_image = f"{registry}/redteam-lab-workstation:latest"
        samba_dc_image = f"{registry}/redteam-lab-samba-dc:latest"

    templates = [
        {
            "name": "Red Team - Kali Attack Box",
            "description": "Kali Linux with KasmVNC desktop and penetration testing tools",
            "os_type": "linux",
            "os_variant": "Kali Linux",
            "vm_type": "container",
            "base_image": "kasmweb/kali-rolling-desktop:1.14.0",
            "default_cpu": 4,
            "default_ram_mb": 4096,
            "default_disk_gb": 60,
            "tags": ["red-team", "attacker", "kali", "desktop"]
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

    # Add the appropriate DC template based on dc_type
    if dc_type == "samba":
        templates.append({
            "name": "Red Team - Samba AD DC",
            "description": "Samba 4 Active Directory DC with misconfigurations (Linux-based, no KVM required)",
            "os_type": "linux",
            "os_variant": "Ubuntu 22.04",
            "vm_type": "container",
            "base_image": samba_dc_image,
            "default_cpu": 2,
            "default_ram_mb": 2048,
            "default_disk_gb": 20,
            "tags": ["red-team", "victim", "samba", "dc", "ad"],
            "config_script": "# Samba AD DC auto-provisions on first startup"
        })
    else:
        templates.append({
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
        })

    return templates

# Default templates for backward compatibility (Windows DC)
TEMPLATES = get_templates(local=False, dc_type="windows")

def get_range_blueprint(subnet_offset: int = 0, dc_type: str = "windows"):
    """
    Get range blueprint with subnet offset for multiple student deployments.

    Args:
        subnet_offset: Adds to second octet (e.g., 0 -> 172.16.x.x, 1 -> 172.17.x.x)
        dc_type: "windows" for Windows DC or "samba" for Samba AD DC

    VM network configuration:
        - Single network: {"network": "name", "ip": "x.x.x.x"}
        - Multi-homed: {"networks": [{"network": "name1", "ip": "x.x.x.x"}, {"network": "name2", "ip": "y.y.y.y"}]}
          First network in the list is the primary network used for VM creation.
    """
    base = 16 + subnet_offset

    # Select DC template and hostname based on dc_type
    if dc_type == "samba":
        dc_template = "Red Team - Samba AD DC"
        dc_hostname = "DC01"
    else:
        dc_template = "Red Team - Windows DC"
        dc_hostname = "WIN-DC01"

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
            # WordPress is multi-homed: accessible from internet (attacker) and dmz
            {
                "template": "Red Team - WordPress Target",
                "hostname": "webserver",
                "networks": [
                    {"network": "dmz", "ip": f"172.{base}.1.10"},
                    {"network": "internet", "ip": f"172.{base}.0.100"}
                ]
            },
            {"template": dc_template, "hostname": dc_hostname, "network": "internal", "ip": f"172.{base}.2.10"},
            {"template": "Red Team - File Server", "hostname": "fileserver", "network": "internal", "ip": f"172.{base}.2.20"},
            # Workstation is multi-homed: on internal network but also reachable from dmz
            {
                "template": "Red Team - Victim Workstation",
                "hostname": "ws01",
                "networks": [
                    {"network": "internal", "ip": f"172.{base}.2.30"},
                    {"network": "dmz", "ip": f"172.{base}.1.30"}
                ]
            }
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

    def attach_network(self, vm_id: str, network_id: str, ip_address: str) -> bool:
        """Attach an additional network interface to a VM."""
        resp = requests.post(
            f"{self.api_url}/vms/{vm_id}/networks",
            headers=self.headers,
            json={"network_id": network_id, "ip_address": ip_address}
        )
        if resp.status_code in (200, 201):
            return True
        else:
            print(f"      Failed to attach network: {resp.status_code} - {resp.text}")
            return False

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

    def import_range(self, template_map: dict, template_details: dict, range_name: str = None, subnet_offset: int = 0, dc_type: str = "windows") -> str:
        """Import the range blueprint."""
        print("\n=== Creating Range ===")

        blueprint = get_range_blueprint(subnet_offset, dc_type)
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

            if not template_id:
                print(f"  [SKIP] {vm['hostname']} - template not found: {template_name}")
                continue

            # Handle multi-homed VMs (multiple networks) vs single network
            if 'networks' in vm:
                # Multi-homed VM: first network is primary
                primary_net = vm['networks'][0]
                additional_nets = vm['networks'][1:]
                network_name = primary_net['network']
                ip_address = primary_net['ip']
            else:
                # Single network VM
                network_name = vm['network']
                ip_address = vm['ip']
                additional_nets = []

            network_id = network_map.get(network_name)
            if not network_id:
                print(f"  [SKIP] {vm['hostname']} - network not found: {network_name}")
                continue

            vm_data = {
                "hostname": vm['hostname'],
                "template_id": template_id,
                "network_id": network_id,
                "ip_address": ip_address,
                "cpu": template.get('default_cpu', 2),
                "ram_mb": template.get('default_ram_mb', 2048),
                "disk_gb": template.get('default_disk_gb', 20)
            }

            net_info = ip_address
            if additional_nets:
                additional_ips = [n['ip'] for n in additional_nets]
                net_info = f"{ip_address} + {', '.join(additional_ips)}"

            print(f"  [CREATE] {vm['hostname']} ({net_info})")
            result = self.create_vm(range_id, vm_data)

            # Attach additional networks for multi-homed VMs
            if result and additional_nets:
                vm_id = result.get('id')
                for add_net in additional_nets:
                    add_network_id = network_map.get(add_net['network'])
                    if add_network_id:
                        print(f"    [ATTACH] {add_net['network']} ({add_net['ip']})")
                        self.attach_network(vm_id, add_network_id, add_net['ip'])
                    else:
                        print(f"    [SKIP] Additional network not found: {add_net['network']}")

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
    parser.add_argument("--dc-type", default=os.environ.get("DC_TYPE", "windows"),
                        choices=["windows", "samba"],
                        help="Domain Controller type: 'windows' (requires KVM) or 'samba' (Linux-based, no KVM)")
    parser.add_argument("--export-json", help="Export templates/range as JSON file instead of importing")

    args = parser.parse_args()

    # Get templates with appropriate image paths and DC type
    templates = get_templates(local=args.local, registry=args.registry, dc_type=args.dc_type)

    # Export mode
    if args.export_json:
        export_data = {
            "templates": templates,
            "range": get_range_blueprint(0, args.dc_type)
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
    print(f"DC Type: {args.dc_type}")
    if not importer.check_connection():
        sys.exit(1)

    # Import templates
    template_map, template_details = importer.import_templates(templates)

    # Create range (unless templates-only)
    if not args.templates_only:
        range_id = importer.import_range(template_map, template_details, args.range_name, args.subnet_offset, args.dc_type)
        if range_id:
            print(f"\n=== Import Complete ===")
            print(f"Range ID: {range_id}")
            print(f"View in CYROID UI to deploy!")
    else:
        print("\n=== Templates Imported ===")
        print("Use CYROID UI to create ranges from these templates")


if __name__ == "__main__":
    main()
