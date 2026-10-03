# Routing Reference

## Route Tables

This architecture uses three explicit route tables. No subnet uses the VPC's
default (main) route table — every subnet has an explicit association.

### 1. Public Route Table

Associated with: Public Subnet A, Public Subnet B

| Destination | Target | Meaning |
|-------------|--------|---------|
| 10.0.0.0/16 | local | VPC-internal traffic stays local |
| 0.0.0.0/0 | igw-xxx | All other traffic → Internet Gateway |

Components in public subnets: ALB, NAT Gateway.

### 2. Private App Route Table

Associated with: Private App Subnet A, Private App Subnet B

| Destination | Target | Meaning |
|-------------|--------|---------|
| 10.0.0.0/16 | local | VPC-internal traffic stays local |
| 0.0.0.0/0 | nat-xxx | All other traffic → NAT Gateway |

Components in private app subnets: EC2 application instances.

### 3. Private DB Route Table

Associated with: Private DB Subnet A, Private DB Subnet B

| Destination | Target | Meaning |
|-------------|--------|---------|
| 10.0.0.0/16 | local | VPC-internal traffic stays local |

No default route — no internet access of any kind.

Components in private DB subnets: RDS instance.

---

## Route Evaluation

AWS route tables use longest-prefix matching. For any destination IP:

1. Find the most specific matching route (longest prefix).
2. Forward to that target.
3. If no route matches: packet is dropped.

For the private app subnets:
- Traffic to 10.0.21.x (DB subnet): matches 10.0.0.0/16 → local
- Traffic to 8.8.8.8 (internet): matches 0.0.0.0/0 → NAT
- Traffic to 10.0.11.x (self): matches 10.0.0.0/16 → local

For the private DB subnets:
- Traffic to 10.0.11.x (app subnet): matches 10.0.0.0/16 → local
- Traffic to 8.8.8.8 (internet): NO MATCH → dropped

This routing isolation is what makes the DB subnet "private" — even if
a security group rule were accidentally opened, there is no internet path.

---

## What Makes a Subnet "Public"

A subnet is not public by definition — it is public because of its route table.

```
Subnet with route: 0.0.0.0/0 → Internet Gateway = PUBLIC
Subnet with route: 0.0.0.0/0 → NAT Gateway     = PRIVATE (outbound-only)
Subnet with no default route                     = FULLY PRIVATE
```

The subnet CIDR, its name, and `map_public_ip_on_launch` setting are all
irrelevant to internet reachability — only the route table matters.

---

## NAT Gateway Path

A private app EC2 instance sends an outbound request to the internet:

```
EC2 (10.0.11.5)
  → Private App Route Table: 0.0.0.0/0 → nat-xxx
  → NAT Gateway in Public Subnet A
  → NAT performs SNAT: src IP becomes 13.x.x.x (Elastic IP)
  → Public Route Table: 0.0.0.0/0 → igw-xxx
  → Internet Gateway
  → Internet

Return path:
  Internet → IGW → NAT Gateway (translates EIP → 10.0.11.5) → EC2
```

The private EC2 never sees the internet directly. The NAT Gateway is
the only component that communicates with the internet on its behalf.

---

## Troubleshooting Routes

```bash
# List all route tables in the VPC
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID"

# Find the route table for a specific subnet
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=$SUBNET_ID"

# Verify the NAT route exists
aws ec2 describe-route-tables \
  --filters "Name=tag:Tier,Values=private-app" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0']"
```
