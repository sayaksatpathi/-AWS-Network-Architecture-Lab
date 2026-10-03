# Traffic Flow

This document traces every significant packet path through the architecture.

---

## 1. Inbound Application Request

A user opens `https://app.example.com/`.

```
Step 1: DNS Lookup
  Client OS → DNS resolver
  DNS resolver → Route 53
  Route 53 returns: ALIAS → aws-network-lab-dev-alb-<id>.ap-south-1.elb.amazonaws.com
  ALB DNS → two public IPs (one per AZ)

Step 2: TCP / TLS Handshake
  Client connects TCP :443 to ALB public IP
  ALB presents ACM certificate for app.example.com
  TLS session established
  ALB Security Group evaluates: TCP 443 from any — ALLOW

Step 3: ALB Processing
  ALB listener :443 receives the request
  TLS is terminated HERE — the private app receives plain HTTP
  ALB selects a target from the target group (round-robin by default)
  ALB evaluates target health — only healthy targets receive traffic

Step 4: Request Forwarded to Private Application
  ALB connects to target EC2 on TCP 8080 (app port)
  Source IP seen by the app: ALB node IP (in the public subnet CIDR)
  App Security Group evaluates: TCP 8080 from ALB SG — ALLOW
  EC2 instance processes the request (no public IP required)

Step 5: Response
  EC2 sends HTTP response to ALB
  ALB re-encrypts response to TLS (or sends over existing TLS session)
  Response delivered to client
```

**Key point:** The EC2 instance never communicates directly with the internet.
The ALB is the only internet-facing component.

---

## 2. Private Egress (Application → Internet via NAT)

An EC2 instance in the private subnet makes an outbound request
(e.g., to download a software update or call an external API).

```
Step 1: Route Lookup on EC2
  Destination: 8.8.8.8 (or any external IP)
  Private App Route Table:
    10.0.0.0/16 → local    (no match)
    0.0.0.0/0   → NAT GW   (match → forward to NAT Gateway)

Step 2: NAT Gateway Processing
  NAT Gateway is in Public Subnet A (10.0.1.0/24)
  NAT replaces source IP: 10.0.11.x → Elastic IP (e.g. 13.x.x.x)
  NAT maintains a connection tracking table for return traffic

Step 3: Route Lookup at NAT Gateway
  Public Route Table:
    10.0.0.0/16 → local    (no match for external destination)
    0.0.0.0/0   → IGW      (match → forward to Internet Gateway)

Step 4: Internet Gateway
  IGW forwards packet to internet
  Source IP seen by the internet: NAT Gateway Elastic IP

Step 5: Return Traffic
  Response arrives at IGW
  Destination IP: NAT Gateway Elastic IP
  IGW delivers to NAT Gateway in Public Subnet A
  NAT Gateway reverses its translation: Elastic IP → 10.0.11.x
  Returns response to the private EC2
```

**Key point:** The private EC2 never needs a public IP. The NAT Gateway
provides the public surface. All return traffic routes back via the same path.

---

## 3. Application → RDS (stays inside VPC)

The application connects to the database.

```
Step 1: Route Lookup on EC2
  Destination: 10.0.21.x (private DB subnet)
  Private App Route Table:
    10.0.0.0/16 → local    (MATCH — stays within VPC)
    0.0.0.0/0   → NAT GW   (not evaluated, first match wins)

Step 2: VPC Local Routing
  Packet delivered directly to DB subnet via VPC fabric
  No NAT Gateway involved
  No Internet Gateway involved
  Traffic NEVER leaves the AWS network

Step 3: Security Group Evaluation at RDS ENI
  DB Security Group:
    Ingress: TCP 5432 from App SG — ALLOW (source matched by SG reference)
    All other ingress: DENY (implicit)

Step 4: Database Response
  RDS responds on the same local path
  Destination: 10.0.11.x (app subnet)
  Private App RT: 10.0.0.0/16 → local — stays inside VPC
```

**Key point:** App-to-RDS traffic uses the VPC-local route (implicit on every
route table). It never traverses NAT or IGW. This is the most efficient and
secure path — no internet exposure possible.

---

## 4. What Happens When the NAT Gateway Disappears

If the NAT Gateway is deleted or the route is removed:

```
EC2 makes outbound request to internet
  ↓
Private App Route Table looks up 0.0.0.0/0
  ↓ If NAT route is gone:
     No matching route → ICMP unreachable or TCP timeout
  ↓ 
Outbound internet fails

But:
  ALB → EC2 (app port) still works — uses VPC-local path
  EC2 → RDS still works — uses VPC-local path
  The application continues serving requests from the ALB
  Only internet egress (package downloads, external APIs) fails
```

This demonstrates that the ALB path (inbound) and NAT path (outbound) are
independent. A NAT failure affects only outbound private egress, not
inbound application traffic.

---

## Network Matrix

| Source           | Destination | Port | Protocol | Allowed? | Mechanism          |
|-----------------|-------------|------|----------|----------|--------------------|
| Internet         | ALB         | 443  | TCP      | ✅ Yes   | ALB SG             |
| Internet         | ALB         | 80   | TCP      | ✅ Yes   | ALB SG (→ redirect)|
| Internet         | EC2 App     | any  | any      | ❌ No    | No public IP; App SG |
| Internet         | RDS         | any  | any      | ❌ No    | Private subnet; DB SG |
| ALB              | EC2 App     | 8080 | TCP      | ✅ Yes   | App SG from ALB SG |
| EC2 App          | RDS         | 5432 | TCP      | ✅ Yes   | DB SG from App SG  |
| EC2 App          | NAT GW      | any  | any      | ✅ Yes   | Private App RT     |
| NAT GW           | Internet    | any  | any      | ✅ Yes   | Public RT → IGW    |
| EC2 App          | Internet    | any  | any      | ✅ Yes*  | Via NAT (outbound) |
| Internet         | NAT GW EIP  | any  | any      | ❌ No    | NAT is one-way     |

*Outbound only via NAT; inbound connections from internet to EC2 are not possible.
