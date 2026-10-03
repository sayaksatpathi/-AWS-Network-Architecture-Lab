#!/bin/bash
set -euo pipefail

# Install Python and pip
dnf install -y python3 python3-pip

# Install application dependencies
pip3 install fastapi uvicorn boto3 psycopg2-binary

# Create application directory
mkdir -p /opt/app

# Write the application
cat > /opt/app/main.py << 'EOF'
import os
import json
import socket
import urllib.request
from fastapi import FastAPI, Response
import uvicorn

app = FastAPI(title="AWS Network Lab")

def get_instance_metadata(path: str, default: str = "unknown") -> str:
    """Fetch EC2 instance metadata via IMDSv2."""
    try:
        # Get token
        token_req = urllib.request.Request(
            "http://169.254.169.254/latest/api/token",
            method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"}
        )
        with urllib.request.urlopen(token_req, timeout=2) as resp:
            token = resp.read().decode()

        # Get metadata
        meta_req = urllib.request.Request(
            f"http://169.254.169.254/latest/meta-data/{path}",
            headers={"X-aws-ec2-metadata-token": token}
        )
        with urllib.request.urlopen(meta_req, timeout=2) as resp:
            return resp.read().decode()
    except Exception:
        return default

@app.get("/")
async def root():
    az = get_instance_metadata("placement/availability-zone")
    instance_id = get_instance_metadata("instance-id")
    return {
        "service": "${project}",
        "status": "healthy",
        "availability_zone": az,
        "instance_id": instance_id,
        "hostname": socket.gethostname(),
        "message": "Hello from the private application tier"
    }

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "${project}"}

@app.get("/az")
async def availability_zone():
    az = get_instance_metadata("placement/availability-zone")
    instance_id = get_instance_metadata("instance-id")
    return {"availability_zone": az, "instance_id": instance_id}

@app.get("/network")
async def network_info():
    """Useful for demonstrating traffic flow through the ALB."""
    az = get_instance_metadata("placement/availability-zone")
    instance_id = get_instance_metadata("instance-id")
    local_ipv4 = get_instance_metadata("local-ipv4")
    mac = get_instance_metadata("mac")
    return {
        "instance_id": instance_id,
        "availability_zone": az,
        "private_ip": local_ipv4,
        "mac": mac,
        "hostname": socket.gethostname()
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=${app_port})
EOF

# Create systemd service
cat > /etc/systemd/system/network-lab-app.service << EOF
[Unit]
Description=AWS Network Lab Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app
ExecStart=/usr/bin/python3 /opt/app/main.py
Restart=always
RestartSec=5
Environment=APP_PORT=${app_port}
Environment=AWS_DEFAULT_REGION=${aws_region}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable network-lab-app
systemctl start network-lab-app

echo "Application started on port ${app_port}"
