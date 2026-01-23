#!/usr/bin/env python3
"""
Import Red Team Training Lab into an existing CYROID installation.

Updated for CYROID v0.13+ which uses Image Library instead of templates.

Usage:
    # Check if required Docker images are built (no CYROID connection needed)
    python import-to-cyroid.py --check-images

    # Set your CYROID API URL and get an auth token first
    export CYROID_API_URL=http://localhost/api/v1
    export CYROID_TOKEN=your-jwt-token

    # Run the import (syncs images + creates range)
    python import-to-cyroid.py --local

    # Import and auto-deploy
    python import-to-cyroid.py --local --deploy

    # Create a reusable blueprint (for GUI deployment)
    python import-to-cyroid.py --local --create-blueprint

    # Full setup: create blueprint + deploy first instance
    python import-to-cyroid.py --local --create-blueprint --deploy
"""

import os
import sys
import json
import argparse
import subprocess
import time
import requests
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
SCENARIOS_DIR = SCRIPT_DIR.parent


# =============================================================================
# Image Definitions
# =============================================================================

# Maps image tag -> container directory for building
IMAGE_DEFINITIONS = {
    "redteam-lab-kali:latest": {
        "dir": "kali",
        "description": "Kali Attack Box with KasmVNC desktop",
        "os_type": "linux",
        "vm_type": "container",
        "cpu": 4,
        "ram_mb": 4096,
        "disk_gb": 60,
    },
    "redteam-lab-wordpress:latest": {
        "dir": "wordpress",
        "description": "WordPress with SQL injection vulnerabilities",
        "os_type": "linux",
        "vm_type": "container",
        "cpu": 2,
        "ram_mb": 2048,
        "disk_gb": 20,
    },
    "redteam-lab-fileserver:latest": {
        "dir": "fileserver",
        "description": "Samba file server with sensitive data",
        "os_type": "linux",
        "vm_type": "container",
        "cpu": 1,
        "ram_mb": 1024,
        "disk_gb": 10,
    },
    "redteam-lab-workstation:latest": {
        "dir": "workstation",
        "description": "Victim workstation (BeEF target)",
        "os_type": "linux",
        "vm_type": "container",
        "cpu": 1,
        "ram_mb": 1024,
        "disk_gb": 10,
    },
    "cyroid/samba-dc:latest": {
        "dir": "samba-dc",
        "description": "Samba 4 Active Directory Domain Controller",
        "os_type": "linux",
        "vm_type": "container",
        "cpu": 2,
        "ram_mb": 2048,
        "disk_gb": 20,
    },
    "alpine:3.19": {
        "dir": None,  # Stock image, no build needed
        "description": "Lightweight redirector",
        "os_type": "linux",
        "vm_type": "container",
        "cpu": 1,
        "ram_mb": 512,
        "disk_gb": 10,
    },
}


def check_docker_images(dc_type: str = "samba") -> bool:
    """Check if required Docker images exist locally."""
    required_images = [
        "redteam-lab-kali:latest",
        "redteam-lab-wordpress:latest",
        "redteam-lab-fileserver:latest",
        "redteam-lab-workstation:latest",
        "alpine:3.19",
    ]
    if dc_type == "samba":
        required_images.append("cyroid/samba-dc:latest")

    print("=== Checking Docker Images ===")
    print()

    missing = []
    present = []

    for image in required_images:
        result = subprocess.run(
            ["docker", "image", "inspect", image],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            present.append(image)
            print(f"  [OK]      {image}")
        else:
            missing.append(image)
            print(f"  [MISSING] {image}")

    print()
    print(f"Summary: {len(present)} present, {len(missing)} missing")

    if missing:
        print()
        print("To build missing images, run:")
        print("  ./build-local.sh")
        return False

    print()
    print("All required images are available!")
    return True


# =============================================================================
# Range Blueprint
# =============================================================================

def get_range_blueprint(dc_type: str = "samba"):
    """
    Get range blueprint configuration.

    VMs reference images by docker_image_tag, which will be resolved to
    base_image_id UUIDs during import.
    """
    return {
        "name": "Red Team Training Lab",
        "description": "Attack training environment: SQLi → Credential theft → Lateral movement → Domain compromise",
        "base_subnet_prefix": "172.16",
        "networks": [
            {"name": "internet", "subnet": "172.16.0.0/24", "gateway": "172.16.0.1", "is_isolated": False},
            {"name": "dmz", "subnet": "172.16.1.0/24", "gateway": "172.16.1.1", "is_isolated": True},
            {"name": "internal", "subnet": "172.16.2.0/24", "gateway": "172.16.2.1", "is_isolated": True},
        ],
        "vms": [
            {
                "hostname": "kali",
                "docker_image_tag": "redteam-lab-kali:latest",
                "network_name": "internet",
                "ip_address": "172.16.0.10",
                "cpu": 4, "ram_mb": 4096, "disk_gb": 60,
                "position_x": 100, "position_y": 200,
            },
            {
                "hostname": "redir1",
                "docker_image_tag": "alpine:3.19",
                "network_name": "internet",
                "ip_address": "172.16.0.20",
                "cpu": 1, "ram_mb": 512, "disk_gb": 10,
                "position_x": 100, "position_y": 300,
            },
            {
                "hostname": "redir2",
                "docker_image_tag": "alpine:3.19",
                "network_name": "internet",
                "ip_address": "172.16.0.21",
                "cpu": 1, "ram_mb": 512, "disk_gb": 10,
                "position_x": 100, "position_y": 400,
            },
            {
                "hostname": "webserver",
                "docker_image_tag": "redteam-lab-wordpress:latest",
                "network_name": "dmz",
                "ip_address": "172.16.1.10",
                "cpu": 2, "ram_mb": 2048, "disk_gb": 20,
                "position_x": 400, "position_y": 200,
                # Multi-homed: also on internet
                "additional_networks": [
                    {"network_name": "internet", "ip_address": "172.16.0.100"}
                ],
            },
            {
                "hostname": "dc01",
                "docker_image_tag": "cyroid/samba-dc:latest",
                "network_name": "internal",
                "ip_address": "172.16.2.10",
                "cpu": 2, "ram_mb": 2048, "disk_gb": 20,
                "position_x": 700, "position_y": 100,
            },
            {
                "hostname": "fileserver",
                "docker_image_tag": "redteam-lab-fileserver:latest",
                "network_name": "internal",
                "ip_address": "172.16.2.20",
                "cpu": 1, "ram_mb": 1024, "disk_gb": 10,
                "position_x": 700, "position_y": 200,
            },
            {
                "hostname": "ws01",
                "docker_image_tag": "redteam-lab-workstation:latest",
                "network_name": "internal",
                "ip_address": "172.16.2.30",
                "cpu": 1, "ram_mb": 1024, "disk_gb": 10,
                "position_x": 700, "position_y": 300,
                # Multi-homed: also on dmz
                "additional_networks": [
                    {"network_name": "dmz", "ip_address": "172.16.1.30"}
                ],
            },
        ],
    }


# =============================================================================
# CYROID API Client
# =============================================================================

class CyroidClient:
    """Client for CYROID API using Image Library."""

    def __init__(self, api_url: str, token: str):
        self.api_url = api_url.rstrip('/')
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        self._image_cache = {}  # docker_image_tag -> UUID

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

    def sync_images_from_cache(self) -> dict:
        """
        Sync Docker images from local cache to Image Library.
        This makes locally-built images available for VM creation.
        """
        print("\n=== Syncing Images to Library ===")
        try:
            resp = requests.post(
                f"{self.api_url}/images/sync-from-cache",
                headers=self.headers
            )
            if resp.status_code == 200:
                result = resp.json()
                print(f"  Docker images synced: {result.get('docker_images_synced', 0)}")
                print(f"  Total synced: {result.get('total_synced', 0)}")
                return result
            else:
                print(f"  Sync failed: {resp.status_code} - {resp.text[:200]}")
                return {}
        except Exception as e:
            print(f"  Sync error: {e}")
            return {}

    def get_base_images(self) -> list:
        """Get all base images from the Image Library."""
        try:
            resp = requests.get(
                f"{self.api_url}/images/base",
                headers=self.headers
            )
            if resp.status_code == 200:
                return resp.json()
            else:
                print(f"Failed to get images: {resp.status_code}")
                return []
        except Exception as e:
            print(f"Error getting images: {e}")
            return []

    def get_image_id_by_tag(self, docker_image_tag: str) -> str:
        """Look up a base image UUID by its docker_image_tag."""
        # Check cache first
        if docker_image_tag in self._image_cache:
            return self._image_cache[docker_image_tag]

        # Fetch all images and build cache
        images = self.get_base_images()
        for img in images:
            tag = img.get('docker_image_tag')
            if tag:
                self._image_cache[tag] = img.get('id')

        return self._image_cache.get(docker_image_tag)

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
            print(f"Failed to create range: {resp.status_code} - {resp.text}")
            return None

    def create_network(self, range_id: str, network: dict) -> dict:
        """Create a network in a range."""
        network_data = {
            "range_id": range_id,
            "name": network["name"],
            "subnet": network["subnet"],
            "gateway": network["gateway"],
            "is_isolated": network.get("is_isolated", True),
        }
        resp = requests.post(
            f"{self.api_url}/networks",
            headers=self.headers,
            json=network_data
        )
        if resp.status_code in (200, 201):
            return resp.json()
        else:
            print(f"  Failed to create network: {resp.status_code} - {resp.text}")
            return None

    def create_vm(self, range_id: str, network_id: str, vm: dict, base_image_id: str) -> dict:
        """Create a VM in a range using Image Library."""
        vm_data = {
            "range_id": range_id,
            "network_id": network_id,
            "base_image_id": base_image_id,
            "hostname": vm["hostname"],
            "ip_address": vm["ip_address"],
            "cpu": vm.get("cpu", 2),
            "ram_mb": vm.get("ram_mb", 2048),
            "disk_gb": vm.get("disk_gb", 20),
            "position_x": vm.get("position_x", 0),
            "position_y": vm.get("position_y", 0),
        }
        resp = requests.post(
            f"{self.api_url}/vms",
            headers=self.headers,
            json=vm_data
        )
        if resp.status_code in (200, 201):
            return resp.json()
        else:
            print(f"  Failed to create VM: {resp.status_code} - {resp.text}")
            return None

    def attach_network_to_vm(self, vm_id: str, network_id: str, ip_address: str) -> bool:
        """Attach an additional network interface to a running VM.

        Note: VM must be in RUNNING state for this to work.
        """
        # API format: POST /vms/{vm_id}/networks/{network_id}?ip_address={ip}
        url = f"{self.api_url}/vms/{vm_id}/networks/{network_id}"
        if ip_address:
            url += f"?ip_address={ip_address}"
        resp = requests.post(url, headers=self.headers)
        if resp.status_code in (200, 201):
            return True
        else:
            print(f"    Failed to attach network: {resp.status_code} - {resp.text}")
            return False

    def deploy_range(self, range_id: str) -> bool:
        """Deploy a range (start all VMs)."""
        resp = requests.post(
            f"{self.api_url}/ranges/{range_id}/deploy",
            headers=self.headers
        )
        if resp.status_code in (200, 201, 202):
            return True
        else:
            print(f"Failed to deploy: {resp.status_code} - {resp.text}")
            return False

    def get_range_status(self, range_id: str) -> dict:
        """Get range status including VM states."""
        resp = requests.get(
            f"{self.api_url}/ranges/{range_id}",
            headers=self.headers
        )
        if resp.status_code == 200:
            return resp.json()
        return None

    def get_range_vms(self, range_id: str) -> list:
        """Get all VMs in a range."""
        resp = requests.get(
            f"{self.api_url}/ranges/{range_id}/vms",
            headers=self.headers
        )
        if resp.status_code == 200:
            return resp.json()
        return []

    def create_blueprint_from_range(self, range_id: str, name: str, base_subnet_prefix: str) -> dict:
        """Create a blueprint from an existing range."""
        resp = requests.post(
            f"{self.api_url}/blueprints",
            headers=self.headers,
            json={
                "range_id": range_id,
                "name": name,
                "base_subnet_prefix": base_subnet_prefix,
            }
        )
        if resp.status_code in (200, 201):
            return resp.json()
        else:
            print(f"Failed to create blueprint: {resp.status_code} - {resp.text}")
            return None

    def list_blueprints(self) -> list:
        """List all blueprints."""
        resp = requests.get(
            f"{self.api_url}/blueprints",
            headers=self.headers
        )
        if resp.status_code == 200:
            return resp.json()
        return []

    def deploy_blueprint_instance(self, blueprint_id: str, name: str) -> dict:
        """Deploy a new instance from a blueprint."""
        resp = requests.post(
            f"{self.api_url}/blueprints/{blueprint_id}/deploy",
            headers=self.headers,
            json={"name": name, "auto_deploy": True}
        )
        if resp.status_code in (200, 201):
            return resp.json()
        else:
            print(f"Failed to deploy blueprint: {resp.status_code} - {resp.text}")
            return None


# =============================================================================
# Import Logic
# =============================================================================

def import_range(client: CyroidClient, blueprint: dict, range_name: str = None) -> tuple:
    """
    Import a range from blueprint using the Image Library.

    Returns (range_id, pending_attachments) if successful, (None, []) otherwise.
    Pending attachments are network interfaces that need to be added after VMs are running.
    """
    pending_attachments = []  # Store multi-homed network attachments for after deployment

    # Step 1: Sync images to library
    client.sync_images_from_cache()

    # Step 2: Verify all required images exist
    print("\n=== Verifying Image Library ===")
    missing_images = []
    image_map = {}  # docker_image_tag -> UUID

    for vm in blueprint["vms"]:
        tag = vm["docker_image_tag"]
        if tag not in image_map:
            image_id = client.get_image_id_by_tag(tag)
            if image_id:
                image_map[tag] = image_id
                print(f"  [OK] {tag} -> {image_id[:8]}...")
            else:
                missing_images.append(tag)
                print(f"  [MISSING] {tag}")

    if missing_images:
        print()
        print("ERROR: Some images are not in the Image Library!")
        print("Make sure you've built them locally and they're accessible to CYROID.")
        print()
        print("Missing images:")
        for img in missing_images:
            print(f"  - {img}")
        return (None, [])

    # Step 3: Create range
    print("\n=== Creating Range ===")
    name = range_name or blueprint["name"]
    description = blueprint.get("description", "")

    range_obj = client.create_range(name, description)
    if not range_obj:
        return (None, [])

    range_id = range_obj["id"]
    print(f"  Created: {name} ({range_id})")

    # Step 4: Create networks
    print("\n=== Creating Networks ===")
    network_map = {}  # network_name -> network_id

    for net in blueprint["networks"]:
        print(f"  [CREATE] {net['name']} ({net['subnet']})")
        result = client.create_network(range_id, net)
        if result:
            network_map[net["name"]] = result["id"]

    # Step 5: Create VMs
    print("\n=== Creating VMs ===")

    for vm in blueprint["vms"]:
        tag = vm["docker_image_tag"]
        base_image_id = image_map.get(tag)
        network_id = network_map.get(vm["network_name"])

        if not base_image_id or not network_id:
            print(f"  [SKIP] {vm['hostname']} - missing image or network")
            continue

        additional_ips = ""
        if "additional_networks" in vm:
            additional_ips = " + " + ", ".join(
                n["ip_address"] for n in vm["additional_networks"]
            )

        print(f"  [CREATE] {vm['hostname']} ({vm['ip_address']}{additional_ips})")
        result = client.create_vm(range_id, network_id, vm, base_image_id)

        # Store pending network attachments (will be applied after VMs are running)
        if result and "additional_networks" in vm:
            vm_id = result["id"]
            for add_net in vm["additional_networks"]:
                add_network_id = network_map.get(add_net["network_name"])
                if add_network_id:
                    pending_attachments.append({
                        "vm_id": vm_id,
                        "vm_hostname": vm["hostname"],
                        "network_id": add_network_id,
                        "network_name": add_net["network_name"],
                        "ip_address": add_net["ip_address"]
                    })

    return range_id, pending_attachments


def apply_pending_attachments(client: CyroidClient, pending_attachments: list) -> bool:
    """Apply pending network attachments to running VMs (for multi-homed VMs)."""
    if not pending_attachments:
        return True

    print("\n=== Attaching Additional Networks ===")
    success = True
    for attach in pending_attachments:
        print(f"  {attach['vm_hostname']}: attaching to {attach['network_name']} ({attach['ip_address']})")
        if not client.attach_network_to_vm(
            attach['vm_id'],
            attach['network_id'],
            attach['ip_address']
        ):
            success = False

    return success


def deploy_and_wait(client: CyroidClient, range_id: str, pending_attachments: list = None, timeout: int = 300) -> bool:
    """Deploy a range and wait for all VMs to be running.

    Args:
        client: CYROID API client
        range_id: ID of the range to deploy
        pending_attachments: List of network attachments to apply after VMs are running
        timeout: Timeout in seconds for waiting
    """
    print("\n=== Deploying Range ===")

    if not client.deploy_range(range_id):
        return False

    print("  Deployment started, waiting for VMs...")

    start_time = time.time()
    while time.time() - start_time < timeout:
        vms = client.get_range_vms(range_id)
        if not vms:
            time.sleep(5)
            continue

        statuses = {}
        for vm in vms:
            status = vm.get("status", "unknown")
            statuses[status] = statuses.get(status, 0) + 1

        total = len(vms)
        running = statuses.get("running", 0)

        status_str = ", ".join(f"{k}:{v}" for k, v in sorted(statuses.items()))
        print(f"  VMs: {running}/{total} running ({status_str})")

        if running == total:
            print("\n  All VMs running!")

            # Apply pending network attachments now that VMs are running
            if pending_attachments:
                if not apply_pending_attachments(client, pending_attachments):
                    print("  Warning: Some network attachments failed")

            return True

        # Check for failures
        failed = statuses.get("failed", 0) + statuses.get("error", 0)
        if failed > 0:
            print(f"\n  WARNING: {failed} VM(s) failed to start")

        time.sleep(5)

    print(f"\n  Timeout after {timeout}s")
    return False


def show_range_info(client: CyroidClient, range_id: str):
    """Display information about a deployed range."""
    print("\n=== Range Information ===")

    range_obj = client.get_range_status(range_id)
    if range_obj:
        print(f"  Name: {range_obj.get('name')}")
        print(f"  Status: {range_obj.get('status')}")
        print(f"  ID: {range_id}")

    vms = client.get_range_vms(range_id)
    if vms:
        print(f"\n  VMs ({len(vms)}):")
        for vm in vms:
            status = vm.get("status", "unknown")
            hostname = vm.get("hostname", "?")
            ip = vm.get("ip_address", "?")
            print(f"    [{status:10}] {hostname:15} {ip}")

    print()
    print("  Access via CYROID UI to view consoles and VNC connections.")


# =============================================================================
# Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="Import Red Team Lab into CYROID (v0.13+)")
    parser.add_argument("--api-url", default=os.environ.get("CYROID_API_URL", "http://localhost/api/v1"))
    parser.add_argument("--token", default=os.environ.get("CYROID_TOKEN"))
    parser.add_argument("--range-name", help="Custom name for the range")
    parser.add_argument("--check-images", action="store_true", help="Check if Docker images exist locally")
    parser.add_argument("--local", action="store_true", help="Use local Docker images")
    parser.add_argument("--deploy", action="store_true", help="Auto-deploy after import")
    parser.add_argument("--create-blueprint", action="store_true",
                        help="Create a reusable blueprint (for GUI deployment)")
    parser.add_argument("--dc-type", default=os.environ.get("DC_TYPE", "samba"),
                        choices=["windows", "samba"],
                        help="Domain Controller type (default: samba)")
    parser.add_argument("--export-json", help="Export blueprint as JSON file")

    args = parser.parse_args()

    # Check images mode
    if args.check_images:
        success = check_docker_images(dc_type=args.dc_type)
        sys.exit(0 if success else 1)

    # Export mode
    if args.export_json:
        blueprint = get_range_blueprint(dc_type=args.dc_type)
        with open(args.export_json, 'w') as f:
            json.dump(blueprint, f, indent=2)
        print(f"Exported to {args.export_json}")
        return

    # Import mode - requires token
    if not args.token:
        print("Error: CYROID_TOKEN not set")
        print()
        print("Get a token by logging into CYROID, then:")
        print("  export CYROID_TOKEN=your-jwt-token")
        print()
        print("Or run with --check-images to verify Docker images without CYROID connection.")
        sys.exit(1)

    # Create client and verify connection
    print(f"CYROID API: {args.api_url}")
    print(f"DC Type: {args.dc_type}")
    print()

    client = CyroidClient(args.api_url, args.token)
    if not client.check_connection():
        sys.exit(1)

    # Get blueprint
    blueprint = get_range_blueprint(dc_type=args.dc_type)

    # Import the range
    result = import_range(client, blueprint, args.range_name)
    if not result or result[0] is None:
        print("\nImport failed!")
        sys.exit(1)

    range_id, pending_attachments = result

    print(f"\n=== Import Complete ===")
    print(f"Range ID: {range_id}")
    if pending_attachments:
        print(f"Pending network attachments: {len(pending_attachments)} (will be applied after deployment)")

    # Create blueprint if requested (for future GUI deployments)
    blueprint_id = None
    if args.create_blueprint:
        print("\n=== Creating Blueprint ===")
        blueprint_name = f"{blueprint['name']} Blueprint"
        bp = client.create_blueprint_from_range(
            range_id=range_id,
            name=blueprint_name,
            base_subnet_prefix=blueprint["base_subnet_prefix"]
        )
        if bp:
            blueprint_id = bp["id"]
            print(f"  Created: {blueprint_name}")
            print(f"  Blueprint ID: {blueprint_id}")
            print()
            print("  You can now deploy new instances from this blueprint via GUI:")
            print("    1. Go to Blueprints page in CYROID")
            print(f"    2. Find '{blueprint_name}'")
            print("    3. Click 'Deploy Instance'")
        else:
            print("  Failed to create blueprint (range still created)")

    # Deploy if requested
    if args.deploy:
        success = deploy_and_wait(client, range_id, pending_attachments)
        if success:
            show_range_info(client, range_id)
        else:
            print("\nDeployment had issues. Check CYROID UI for details.")
            sys.exit(1)
    else:
        print()
        print("Range created but not deployed.")
        print("To deploy, either:")
        print(f"  - Run: python import-to-cyroid.py --local --deploy")
        print(f"  - Or use the CYROID UI to deploy the range")
        if blueprint_id:
            print(f"  - Or deploy new instances from the blueprint via GUI")


if __name__ == "__main__":
    main()
