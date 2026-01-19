#!/usr/bin/env python3
"""
Package Red Team Training Lab as a CYROID blueprint with Dockerfiles.

Creates a self-contained blueprint ZIP that CYROID can import and automatically
build all required container images.
"""
import json
import os
import shutil
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
CONTAINERS_DIR = SCRIPT_DIR.parent / "containers"
OUTPUT_DIR = SCRIPT_DIR.parent.parent.parent  # Root of repo


def get_blueprint_config():
    """Return the blueprint configuration."""
    return {
        "name": "Red Team Training Lab",
        "description": "Complete red team training environment with Kali attack box, "
                      "WordPress SQLi target, Samba DC, file server, and victim workstation. "
                      "Attack path: SQLi → Credential theft → Lateral movement → Domain compromise",
        "version": 1,
        "base_subnet_prefix": "172.16",
        "next_offset": 0,
        "config": {
            "networks": [
                {"name": "internet", "subnet": "172.16.0.0/24", "gateway": "172.16.0.1", "is_isolated": True},
                {"name": "dmz", "subnet": "172.16.1.0/24", "gateway": "172.16.1.1", "is_isolated": True},
                {"name": "internal", "subnet": "172.16.2.0/24", "gateway": "172.16.2.1", "is_isolated": True},
            ],
            "vms": [
                {
                    "hostname": "kali",
                    "ip_address": "172.16.0.10",
                    "network_name": "internet",
                    "template_name": "Red Team - Kali Attack Box",
                    "cpu": 4, "ram_mb": 4096, "disk_gb": 60,
                    "position_x": 100, "position_y": 200,
                },
                {
                    "hostname": "redir1",
                    "ip_address": "172.16.0.20",
                    "network_name": "internet",
                    "template_name": "Red Team - Redirector",
                    "cpu": 1, "ram_mb": 512, "disk_gb": 10,
                    "position_x": 100, "position_y": 300,
                },
                {
                    "hostname": "redir2",
                    "ip_address": "172.16.0.21",
                    "network_name": "internet",
                    "template_name": "Red Team - Redirector",
                    "cpu": 1, "ram_mb": 512, "disk_gb": 10,
                    "position_x": 100, "position_y": 400,
                },
                {
                    "hostname": "webserver",
                    "ip_address": "172.16.1.10",
                    "network_name": "dmz",
                    "template_name": "Red Team - WordPress Target",
                    "cpu": 2, "ram_mb": 2048, "disk_gb": 20,
                    "position_x": 400, "position_y": 200,
                },
                {
                    "hostname": "dc01",
                    "ip_address": "172.16.2.10",
                    "network_name": "internal",
                    "template_name": "Samba DC",
                    "cpu": 2, "ram_mb": 2048, "disk_gb": 20,
                    "position_x": 700, "position_y": 100,
                },
                {
                    "hostname": "fileserver",
                    "ip_address": "172.16.2.20",
                    "network_name": "internal",
                    "template_name": "Red Team - File Server",
                    "cpu": 1, "ram_mb": 1024, "disk_gb": 10,
                    "position_x": 700, "position_y": 200,
                },
                {
                    "hostname": "ws01",
                    "ip_address": "172.16.2.30",
                    "network_name": "internal",
                    "template_name": "Red Team - Victim Workstation",
                    "cpu": 1, "ram_mb": 1024, "disk_gb": 10,
                    "position_x": 700, "position_y": 300,
                },
            ],
            "router": {"enabled": True, "dhcp_enabled": False},
            "msel": None,
        }
    }


def get_templates():
    """Return template definitions."""
    return [
        {
            "name": "Red Team - Kali Attack Box",
            "description": "Kali Linux with pre-installed attack tools",
            "os_type": "linux",
            "os_variant": "Kali Linux",
            "base_image": "redteam-lab-kali:latest",
            "vm_type": "container",
            "linux_distro": "kali",
            "boot_mode": None,
            "disk_type": None,
            "default_cpu": 4,
            "default_ram_mb": 4096,
            "default_disk_gb": 60,
            "config_script": None,
            "tags": ["attack", "kali", "red-team"],
        },
        {
            "name": "Red Team - Redirector",
            "description": "Lightweight Alpine redirector for C2 traffic",
            "os_type": "linux",
            "os_variant": "Alpine Linux",
            "base_image": "alpine:latest",
            "vm_type": "container",
            "linux_distro": "alpine",
            "boot_mode": None,
            "disk_type": None,
            "default_cpu": 1,
            "default_ram_mb": 512,
            "default_disk_gb": 10,
            "config_script": "apk add --no-cache socat iptables && echo 1 > /proc/sys/net/ipv4/ip_forward",
            "tags": ["redirector", "c2", "red-team"],
        },
        {
            "name": "Red Team - WordPress Target",
            "description": "WordPress with SQL injection vulnerabilities",
            "os_type": "linux",
            "os_variant": "Ubuntu 22.04",
            "base_image": "redteam-lab-wordpress:latest",
            "vm_type": "container",
            "linux_distro": "ubuntu",
            "boot_mode": None,
            "disk_type": None,
            "default_cpu": 2,
            "default_ram_mb": 2048,
            "default_disk_gb": 20,
            "config_script": None,
            "tags": ["target", "wordpress", "sqli"],
        },
        {
            "name": "Red Team - File Server",
            "description": "Samba file server with sensitive data",
            "os_type": "linux",
            "os_variant": "Ubuntu 22.04",
            "base_image": "redteam-lab-fileserver:latest",
            "vm_type": "container",
            "linux_distro": "ubuntu",
            "boot_mode": None,
            "disk_type": None,
            "default_cpu": 1,
            "default_ram_mb": 1024,
            "default_disk_gb": 10,
            "config_script": None,
            "tags": ["target", "fileserver", "smb"],
        },
        {
            "name": "Red Team - Victim Workstation",
            "description": "Simulated workstation that browses web periodically",
            "os_type": "linux",
            "os_variant": "Ubuntu 22.04",
            "base_image": "redteam-lab-workstation:latest",
            "vm_type": "container",
            "linux_distro": "ubuntu",
            "boot_mode": None,
            "disk_type": None,
            "default_cpu": 1,
            "default_ram_mb": 1024,
            "default_disk_gb": 10,
            "config_script": None,
            "tags": ["target", "workstation", "victim"],
        },
        {
            "name": "Samba DC",
            "description": "Samba 4 Active Directory Domain Controller",
            "os_type": "linux",
            "os_variant": "Ubuntu 22.04",
            "base_image": "cyroid/samba-dc:latest",
            "vm_type": "container",
            "linux_distro": "ubuntu",
            "boot_mode": None,
            "disk_type": None,
            "default_cpu": 2,
            "default_ram_mb": 2048,
            "default_disk_gb": 20,
            "config_script": None,
            "tags": ["dc", "samba", "ad"],
        },
    ]


# Map template base_image to container directory
IMAGE_TO_DIR = {
    "redteam-lab-kali:latest": "kali",
    "redteam-lab-wordpress:latest": "wordpress",
    "redteam-lab-fileserver:latest": "fileserver",
    "redteam-lab-workstation:latest": "workstation",
    "cyroid/samba-dc:latest": "samba-dc",
}


def safe_image_name(image_name: str) -> str:
    """Convert image name to safe directory name."""
    return image_name.replace("/", "_").replace(":", "_")


def copy_dockerfile_context(image_name: str, dest_dir: Path) -> bool:
    """Copy Dockerfile and context for an image."""
    if image_name not in IMAGE_TO_DIR:
        return False

    container_dir = CONTAINERS_DIR / IMAGE_TO_DIR[image_name]
    if not container_dir.exists():
        print(f"  Warning: Container dir not found: {container_dir}")
        return False

    safe_name = safe_image_name(image_name)
    image_dest = dest_dir / safe_name

    # Copy the entire container directory
    shutil.copytree(container_dir, image_dest)
    print(f"  Copied {container_dir} -> dockerfiles/{safe_name}/")
    return True


def main():
    print("Packaging Red Team Training Lab Blueprint")
    print("=" * 50)

    # Create temp directory for packaging
    temp_dir = Path(tempfile.mkdtemp(prefix="rtl-blueprint-"))

    try:
        # Get blueprint and templates
        blueprint = get_blueprint_config()
        templates = get_templates()

        # Create manifest
        manifest = {
            "version": "1.0",
            "export_type": "blueprint",
            "created_at": datetime.utcnow().isoformat() + "Z",
            "created_by": "red-team-training-lab",
            "blueprint_name": blueprint["name"],
            "template_count": len(templates),
            "checksums": {},
        }

        # Create full export structure
        export_data = {
            "manifest": manifest,
            "blueprint": blueprint,
            "templates": templates,
        }

        # Write blueprint.json
        print("\nWriting blueprint.json...")
        blueprint_json = json.dumps(export_data, indent=2)
        (temp_dir / "blueprint.json").write_text(blueprint_json)

        # Write manifest.json
        print("Writing manifest.json...")
        (temp_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))

        # Write individual template files
        templates_dir = temp_dir / "templates"
        templates_dir.mkdir()
        print("Writing template files...")
        for template in templates:
            safe_name = template["name"].replace("/", "_").replace(" ", "_")
            (templates_dir / f"{safe_name}.json").write_text(json.dumps(template, indent=2))

        # Copy Dockerfiles
        print("\nCopying Dockerfiles...")
        dockerfiles_dir = temp_dir / "dockerfiles"
        dockerfiles_dir.mkdir()

        for template in templates:
            image = template.get("base_image")
            if image and image in IMAGE_TO_DIR:
                copy_dockerfile_context(image, dockerfiles_dir)

        # Create ZIP archive
        output_path = OUTPUT_DIR / "red-team-training-lab.blueprint.zip"
        print(f"\nCreating ZIP archive: {output_path}")

        with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for root, dirs, files in os.walk(temp_dir):
                for file in files:
                    file_path = Path(root) / file
                    arcname = file_path.relative_to(temp_dir)
                    zf.write(file_path, arcname)

        # Show archive contents
        print("\nArchive contents:")
        with zipfile.ZipFile(output_path, "r") as zf:
            for info in zf.infolist():
                print(f"  {info.filename} ({info.file_size} bytes)")

        print(f"\n✓ Blueprint created: {output_path}")
        print(f"  Size: {output_path.stat().st_size / 1024:.1f} KB")

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
