# AWS Secure Multi-Tier Network — Architecture Diagram

## Full Architecture

```mermaid
graph TB
    Internet(["🌐 Internet"])

    subgraph Route53["Route 53"]
        DNS["DNS\napp.example.com → ALB"]
    end

    subgraph ACM["ACM"]
        TLS["TLS Certificate\napp.example.com"]
    end

    subgraph VPC["VPC  10.0.0.0/16"]
        subgraph AZ_A["Availability Zone — ap-south-1a"]
            subgraph PubA["Public Subnet A  10.0.1.0/24"]
                NAT["NAT Gateway\n+ Elastic IP"]
                ALB_A["ALB Node A"]
            end
            subgraph AppA["Private App Subnet A  10.0.11.0/24"]
                EC2_A["EC2 App-1\n(no public IP)"]
            end
            subgraph DBA["Private DB Subnet A  10.0.21.0/24"]
                RDS_P["RDS Primary\n(private)"]
            end
        end

        subgraph AZ_B["Availability Zone — ap-south-1b"]
            subgraph PubB["Public Subnet B  10.0.2.0/24"]
                ALB_B["ALB Node B"]
            end
            subgraph AppB["Private App Subnet B  10.0.12.0/24"]
                EC2_B["EC2 App-2\n(no public IP)"]
            end
            subgraph DBB["Private DB Subnet B  10.0.22.0/24"]
                RDS_S["RDS Standby\n(Multi-AZ optional)"]
            end
        end

        IGW["Internet Gateway"]
        PubRT["Public Route Table\n0.0.0.0/0 → IGW"]
        PrivAppRT["Private App RT\n0.0.0.0/0 → NAT"]
        PrivDBRT["Private DB RT\nVPC local only"]

        ALB["Application Load Balancer\n(internet-facing, :80/:443)"]
        TG["Target Group\n(health: /health)"]
    end

    Internet -->|HTTPS :443| DNS
    DNS -->|alias| ALB
    TLS -->|cert| ALB
    ALB --> ALB_A & ALB_B
    ALB_A & ALB_B --> TG
    TG --> EC2_A & EC2_B
    EC2_A -->|TCP 5432| RDS_P
    EC2_B -->|TCP 5432| RDS_P
    RDS_P -.->|failover| RDS_S

    EC2_A & EC2_B -->|outbound| PrivAppRT
    PrivAppRT --> NAT
    NAT --> PubRT
    PubRT --> IGW
    IGW --> Internet

    PubA & PubB --> PubRT
    AppA & AppB --> PrivAppRT
    DBA & DBB --> PrivDBRT
```

## Security Chain

```mermaid
graph LR
    Internet(["Internet"])
    ALB_SG["ALB SG\nTCP 443 from 0.0.0.0/0"]
    App_SG["App SG\nTCP 8080 from ALB SG only"]
    DB_SG["DB SG\nTCP 5432 from App SG only"]
    RDS["RDS"]

    Internet --> ALB_SG --> App_SG --> DB_SG --> RDS
```

## Traffic Flows

### Inbound (Internet → Application)

```
Client
  ↓ DNS lookup: app.example.com
  ↓
Route 53 (alias → ALB DNS)
  ↓
ALB public IP (:443)
  ↓ TLS termination
ALB Security Group (allows 443 from 0.0.0.0/0)
  ↓
ALB Listener → Target Group
  ↓ health checks pass
App Security Group (allows 8080 from ALB SG)
  ↓
EC2 App Instance (private subnet, no public IP)
  ↓
Response (same path, reversed)
```

### Private Egress (App → Internet via NAT)

```
EC2 App Instance (10.0.11.x)
  ↓
Private App Route Table
  → 0.0.0.0/0 → NAT Gateway
  ↓
NAT Gateway (in Public Subnet A, has EIP)
  ↓
Public Route Table
  → 0.0.0.0/0 → Internet Gateway
  ↓
Internet Gateway
  ↓
Internet (source IP = NAT Gateway EIP)
```

### App → RDS (VPC-local, never touches internet)

```
EC2 App Instance (10.0.11.x)
  ↓
App Security Group (egress: allows all to VPC)
  ↓
VPC Local Route (10.0.0.0/16 → local)
  ↓
DB Security Group (ingress: allows 5432 from App SG)
  ↓
RDS Instance (10.0.21.x, private subnet)
```
