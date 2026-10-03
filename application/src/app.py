"""
AWS Network Lab — minimal application tier.

Purpose: make network behavior TESTABLE, not build a production service.
Routes expose: availability zone, instance metadata, DB connectivity check.
"""
import os
import socket
import urllib.request
from fastapi import FastAPI, HTTPException
import uvicorn

app = FastAPI(
    title="AWS Network Lab",
    description="Demonstrates multi-AZ ALB routing through private application tier",
)

APP_PORT = int(os.getenv("APP_PORT", "8080"))
DB_HOST = os.getenv("DB_HOST", "")
DB_PORT = int(os.getenv("DB_PORT", "5432"))


def _imds(path: str, default: str = "unknown") -> str:
    """Fetch EC2 instance metadata via IMDSv2."""
    try:
        req = urllib.request.Request(
            "http://169.254.169.254/latest/api/token",
            method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
        )
        with urllib.request.urlopen(req, timeout=2) as r:
            token = r.read().decode()
        req2 = urllib.request.Request(
            f"http://169.254.169.254/latest/meta-data/{path}",
            headers={"X-aws-ec2-metadata-token": token},
        )
        with urllib.request.urlopen(req2, timeout=2) as r:
            return r.read().decode()
    except Exception:
        return default


@app.get("/")
async def root():
    """Identity + AZ — proves which instance/AZ served this request."""
    return {
        "service": "aws-network-lab",
        "status": "healthy",
        "availability_zone": _imds("placement/availability-zone"),
        "instance_id": _imds("instance-id"),
        "private_ip": _imds("local-ipv4"),
        "hostname": socket.gethostname(),
    }


@app.get("/health")
async def health():
    """ALB health-check endpoint. Must return 200 for the target to be healthy."""
    return {"status": "healthy"}


@app.get("/az")
async def az():
    """Demonstrates ALB round-robin across AZs. Reload repeatedly to see both AZs."""
    return {
        "availability_zone": _imds("placement/availability-zone"),
        "instance_id": _imds("instance-id"),
    }


@app.get("/db-check")
async def db_check():
    """
    Validates TCP reachability to RDS.
    Proves: App SG → DB SG path works without exposing credentials.
    """
    if not DB_HOST:
        return {"status": "skipped", "reason": "DB_HOST not configured"}

    try:
        sock = socket.create_connection((DB_HOST, DB_PORT), timeout=3)
        sock.close()
        return {
            "status": "reachable",
            "host": DB_HOST,
            "port": DB_PORT,
            "message": "TCP connection to RDS succeeded — App SG → DB SG path is open",
        }
    except Exception as e:
        raise HTTPException(
            status_code=503,
            detail={
                "status": "unreachable",
                "host": DB_HOST,
                "port": DB_PORT,
                "error": str(e),
                "diagnosis": "Check App SG egress and DB SG ingress rules",
            },
        )


@app.get("/egress-check")
async def egress_check():
    """
    Validates outbound internet access via NAT Gateway.
    Proves: Private App → NAT → IGW → Internet path works.
    """
    try:
        req = urllib.request.Request("https://checkip.amazonaws.com", method="GET")
        with urllib.request.urlopen(req, timeout=5) as r:
            public_ip = r.read().decode().strip()
        return {
            "status": "success",
            "public_ip": public_ip,
            "message": "Outbound internet works. This IP is the NAT Gateway's Elastic IP.",
            "path": "Private App → Private Route Table → NAT Gateway → IGW → Internet",
        }
    except Exception as e:
        raise HTTPException(
            status_code=503,
            detail={
                "status": "failed",
                "error": str(e),
                "diagnosis": "Check Private App route table — 0.0.0.0/0 must point to NAT Gateway",
            },
        )


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=APP_PORT)
