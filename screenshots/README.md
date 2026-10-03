# Screenshots

Screenshots in this directory are captured from the AWS Console after deployment.
They cannot be automated — each requires the lab to be running in an AWS account.

## Required Screenshots

After running `terraform apply` and verifying with `make verify`, capture:

### 1. VPC Overview (`vpc-overview.png`)

**Location:** VPC → Your VPCs → select `aws-network-lab-dev`

**Shows:** VPC CIDR (10.0.0.0/16), DNS hostnames enabled, DNS resolution enabled

### 2. Subnet Layout (`subnet-layout.png`)

**Location:** VPC → Subnets → filter by VPC

**Shows:** All 6 subnets, their CIDRs, AZs, and route table associations

### 3. Route Tables (`route-tables.png`)

**Location:** VPC → Route Tables → filter by VPC

**Shows:** The 3 route tables (public, private-app, private-db) with their routes

**Capture the Routes tab for each table to show:**
- Public: 0.0.0.0/0 → igw-xxx
- Private App: 0.0.0.0/0 → nat-xxx
- Private DB: local only

### 4. Security Groups (`security-groups.png`)

**Location:** EC2 → Security Groups → filter by VPC

**Shows:** The 3 SGs (ALB, App, DB) with their inbound rules demonstrating
the SG-to-SG reference chain

### 5. ALB Target Health (`alb-target-health.png`)

**Location:** EC2 → Load Balancers → select ALB → Target Groups tab →
select target group → Targets tab

**Shows:** Both app instances in "healthy" state

### 6. RDS Private Placement (`rds-private.png`)

**Location:** RDS → Databases → select the instance → Connectivity & security tab

**Shows:** "Publicly accessible: No", VPC, subnet group with private DB subnets

### 7. NAT Gateway (`nat-gateway.png`)

**Location:** VPC → NAT Gateways → select the NAT GW

**Shows:** State "Available", Public IP (Elastic IP), located in public subnet

### 8. EC2 Instances (No Public IPs) (`ec2-no-public-ip.png`)

**Location:** EC2 → Instances → filter by tag Name: aws-network-lab-dev-app-*

**Shows:** Both app instances with "Public IPv4 address: -" (no public IP)

## Capture Instructions

1. Deploy the lab: `terraform -chdir=terraform/environments/dev apply`
2. Verify healthy: `make verify && make test-ingress`
3. Open the AWS Console in your browser
4. Navigate to each location listed above
5. Take a screenshot and save with the filename shown
6. Place each screenshot in this `screenshots/` directory

## Note on Authenticity

These screenshots document a real deployment. Do not substitute:
- Mock screenshots
- Sample console images
- AI-generated console simulations

The screenshots prove the lab was actually deployed and the network
topology was verified in a real AWS account.
