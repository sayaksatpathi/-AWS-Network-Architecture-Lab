# AWS Secure Multi-Tier Network Architecture Lab

> I designed and operated a multi-AZ AWS VPC with public and private subnet tiers,
> implemented routing through Internet and NAT Gateways, secured application and
> database layers using least-privilege Security Groups and NACLs, exposed private
> application instances through an internet-facing ALB, placed RDS in private
> database subnets, and diagnosed real network failures involving security groups,
> routes, DNS, NAT, target groups, and TLS.

---

## What This Lab Proves

This is not a Terraform template collection. It is an operational AWS networking
lab that demonstrates understanding of:

- How packets actually flow from the internet to a private application
- Why private subnets need NAT, and what happens when NAT disappears
- How the ALB decouples public internet exposure from private application placement
- How security groups and NACLs provide layered network security
- How to diagnose six categories of real AWS network failures

---

## Architecture

```
                         INTERNET
                             │
                     DNS lookup
                             │
                         ROUTE 53
                     (app.example.com → ALB)
                             │
                      HTTPS / TLS (ACM)
                             │
                    ┌────────▼─────────┐
                    │  APPLICATION     │
                    │  LOAD BALANCER   │  ← Internet-facing, in public subnets
                    │  :443 / :80      │
                    └───┬─────────┬───┘
                        │         │
              ┌─────────▼──┐  ┌───▼──────────┐
              │ Public     │  │ Public        │
              │ Subnet A   │  │ Subnet B      │
              │ 10.0.1.0/24│  │ 10.0.2.0/24  │
              │ [NAT GW]   │  │               │
              └────────────┘  └───────────────┘
                        │         │
              ┌─────────▼──────────▼──────────┐
              │       TARGET GROUP             │
              │    (health: /health)           │
              └───────┬──────────────┬─────────┘
                      │              │
           ┌──────────▼──┐  ┌────────▼───────┐
           │ Private App │  │ Private App    │
           │ Subnet A    │  │ Subnet B       │
           │ 10.0.11.0   │  │ 10.0.12.0      │
           │ [EC2 App-1] │  │ [EC2 App-2]    │  ← No public IPs
           └──────┬──────┘  └────────┬───────┘
                  │                  │
                  └──────────┬───────┘
                             │ TCP 5432 (VPC-local)
              ┌──────────────▼──────────────┐
              │      DB SUBNET GROUP         │
              ├─────────────────────────────┤
              │ DB Subnet A  │ DB Subnet B   │
              │ 10.0.21.0    │ 10.0.22.0     │
              │ [RDS Primary]│ [RDS Standby] │  ← Private, no internet route
              └─────────────────────────────┘
```

### Private Egress Path

```
EC2 App Instance (10.0.11.x)
  → Private App Route Table (0.0.0.0/0 → NAT GW)
  → NAT Gateway (Public Subnet A, Elastic IP)
  → Public Route Table (0.0.0.0/0 → IGW)
  → Internet Gateway
  → Internet (source IP = NAT EIP)
```

---

## CIDR Plan

| Resource              | CIDR          | AZ     | Route to Internet   |
|----------------------|---------------|--------|---------------------|
| VPC                   | 10.0.0.0/16   | -      | -                   |
| Public Subnet A       | 10.0.1.0/24   | AZ-a   | → Internet Gateway  |
| Public Subnet B       | 10.0.2.0/24   | AZ-b   | → Internet Gateway  |
| Private App Subnet A  | 10.0.11.0/24  | AZ-a   | → NAT Gateway only  |
| Private App Subnet B  | 10.0.12.0/24  | AZ-b   | → NAT Gateway only  |
| Private DB Subnet A   | 10.0.21.0/24  | AZ-a   | None                |
| Private DB Subnet B   | 10.0.22.0/24  | AZ-b   | None                |

---

## Route Tables

| Route Table         | Routes                                  | Purpose              |
|--------------------|----------------------------------------|----------------------|
| Public RT           | 10.0.0.0/16 → local, 0.0.0.0/0 → IGW  | Public subnets       |
| Private App RT      | 10.0.0.0/16 → local, 0.0.0.0/0 → NAT  | App tier egress      |
| Private DB RT       | 10.0.0.0/16 → local                    | DB isolation         |

---

## Security Chain

```
Internet → ALB SG (443 from any) → App SG (8080 from ALB SG) → DB SG (5432 from App SG)
```

Security groups reference each other (SG-to-SG), not CIDRs.
This means only ALB-member ENIs can reach the app port, and only app-member
ENIs can reach the database port.

---

## Deployment

### Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.5.0
- AWS account with appropriate permissions

### Steps

```bash
# 1. Clone
git clone https://github.com/sayaksatpathi/-AWS-Network-Architecture-Lab.git
cd AWS\ Network\ Architecture\ Lab

# 2. Configure
cp terraform/environments/dev/terraform.tfvars.example \
   terraform/environments/dev/terraform.tfvars
# Edit terraform.tfvars — set your region, optionally domain/TLS settings

# 3. Initialize
cd terraform/environments/dev
terraform init

# 4. Plan
terraform plan

# 5. Apply (~8 minutes, mostly RDS creation)
terraform apply

# 6. Validate
cd ../../..
make verify
```

### DNS and TLS (Optional)

If you have a Route 53 hosted zone, set in `terraform.tfvars`:

```hcl
create_dns  = true
create_tls  = true
domain_name = "yourdomain.com"
subdomain   = "app"
```

Without a domain, the application is still fully functional via the ALB DNS name.
All network behavior (routing, NAT, SGs, NACLs) works identically — only the
custom URL and TLS certificate are missing.

---

## Verification

After deployment, run:

```bash
# Full network topology check
make verify

# Test public ingress through ALB
make test-ingress

# Test private egress through NAT Gateway
make test-egress

# Verify security model
make test-security
```

Or directly:

```bash
# Get ALB DNS name
ALB_DNS=$(terraform -chdir=terraform/environments/dev output -raw alb_dns_name)

# Health check
curl http://$ALB_DNS/health
# → {"status":"healthy"}

# AZ identity
curl http://$ALB_DNS/az
# → {"availability_zone":"ap-south-1a","instance_id":"i-..."}

# Egress check (proves NAT path)
curl http://$ALB_DNS/egress-check
# → {"status":"success","public_ip":"<NAT-EIP>","path":"Private App → NAT → IGW → Internet"}

# DB connectivity
curl http://$ALB_DNS/db-check
# → {"status":"reachable","host":"<rds-endpoint>","port":5432}
```

---

## Troubleshooting Lab

Six intentional failures with diagnosis and recovery. Full details in [docs/troubleshooting.md](docs/troubleshooting.md).

| Scenario | Failure | Symptom | Key Tool |
|---------|---------|---------|---------|
| 1 | App SG: ALB rule removed | Targets unhealthy, 502 | describe-target-health |
| 2 | Route: NAT route deleted | Egress fails, ALB still works | describe-route-tables |
| 3 | DNS: Wrong alias target | resolve fails / wrong IP | dig, nslookup |
| 4 | NAT Gateway deleted | Egress fails, app still serves | describe-nat-gateways |
| 5 | Target group: wrong health path | Targets unhealthy, reason=404 | describe-target-health |
| 6 | TLS: Certificate mismatch | curl SSL error | openssl s_client |

---

## Interview Questions This Lab Answers

### Why is the ALB public but the application private?

The ALB is the only component that needs to accept internet traffic. By placing
the ALB in public subnets and the application in private subnets, we expose the
minimum necessary attack surface. The application is not reachable from the
internet even if its SG were misconfigured — there is no internet route to the
private subnets, and the instances have no public IPs.

### Why does the private subnet need NAT?

Private subnets have no route to the Internet Gateway, so instances in them cannot
initiate outbound internet connections on their own. NAT provides outbound-only
internet access: the private instance's traffic is source-NAT'd to the NAT
Gateway's Elastic IP before leaving the VPC. Return traffic is translated back.
This lets private instances pull updates or call external APIs without being
reachable from the internet.

### Why can't the private application simply use an IGW?

Adding a route `0.0.0.0/0 → IGW` to the private app route table would make those
subnets public (instances would need public IPs to use the IGW). The application
would become directly reachable from the internet, defeating the point of private
subnets. The NAT path provides egress without inbound reachability.

### Why is RDS in private subnets?

Database servers should never be directly reachable from the internet:
1. Databases contain sensitive data
2. They expose authentication surfaces (password brute-force attacks)
3. Placing them in private subnets means even a misconfigured security group cannot
   lead to internet exposure — there is no internet route in the DB subnet

### Why are there two Availability Zones?

Single-AZ architectures fail when that AZ has an outage. Using two AZs means:
- The ALB distributes traffic across both AZs
- If one AZ fails, the other continues serving requests
- RDS can use Multi-AZ for automatic failover
- EC2 instances in both AZs provide redundancy

### What is the difference between a route table and a security group?

**Route table:** Controls WHERE packets are forwarded at the VPC router level.
Operates before the packet reaches its destination. Determines which network
gateway handles the traffic.

**Security group:** Controls WHETHER a packet is ALLOWED at the destination ENI.
Operates at the destination. Is stateful — tracks connection state for return traffic.

### What is the difference between a security group and a NACL?

| Security Group | NACL |
|---------------|------|
| Resource-level (ENI) | Subnet-level |
| Stateful | Stateless |
| Allow rules only | Allow and Deny rules |
| All rules evaluated | First-match wins |
| Automatic return traffic | Must allow ephemeral ports explicitly |

### How does an ALB decide where to send traffic?

The ALB uses the configured routing algorithm (default: round-robin) across
all healthy targets in the target group. Before forwarding, it checks target
health. Unhealthy targets are excluded. The target group health check (`/health`
returning 200) is what defines "healthy".

### What happens if the NAT Gateway disappears?

- Inbound traffic: **unaffected** — the ALB→App path uses VPC-local routing
- App→DB: **unaffected** — VPC-local routing
- App outbound internet: **fails** — packets match the 0.0.0.0/0 route but the
  NAT Gateway is gone (blackhole route). External API calls and package downloads fail.

### What happens if the application security group blocks the ALB?

The ALB's health checks cannot reach the app instances. All targets become
unhealthy. The ALB returns 503 to clients. The fix is to restore the inbound
rule allowing the ALB SG on the app port.

### How do you diagnose a DNS problem?

```bash
# 1. Can the hostname be resolved?
dig app.example.com +short
nslookup app.example.com

# 2. What does it resolve to?
# Compare to expected ALB DNS name

# 3. Check Route 53 records
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>

# 4. Test with the ALB DNS directly (bypasses DNS)
curl http://<alb-dns>/health
```

If `curl http://<alb-dns>/health` works but `curl https://app.example.com/health`
fails, the problem is DNS or TLS — not the application or ALB configuration.

### How do you distinguish a DNS problem from an ALB problem?

```
DNS problem:   dig returns NXDOMAIN or wrong IP
ALB problem:   dig returns correct IP, but curl to ALB directly also fails
App problem:   ALB DNS works, ALB returns 5xx, target health shows unhealthy
```

### How do you diagnose an unhealthy target?

```bash
aws elbv2 describe-target-health --target-group-arn <arn>
# Look at: State, Reason, Description

# Reasons:
# Target.ResponseCodeMismatch → app returned wrong status (check health check path)
# Target.Timeout              → SG or NACL blocking health check (TCP not reaching app)
# Target.FailedHealthChecks   → App not running (check EC2 process)
```

### How would you diagnose a TLS failure?

```bash
# See what certificate the ALB is presenting
openssl s_client -connect <alb-dns>:443 -servername app.example.com

# Check if the CN matches the hostname
# Check expiry date
# Compare with ACM certificate in console

curl -v https://app.example.com/health 2>&1 | grep -i "ssl\|tls\|cert"
```

### How would you prove whether a network path is reachable?

Use **VPC Reachability Analyzer**:
```bash
aws ec2 create-network-insights-path \
  --source <alb-eni> --destination <app-instance> \
  --protocol tcp --destination-port 8080
aws ec2 start-network-insights-analysis --network-insights-path-id <path-id>
```

Returns either "reachable" or "not reachable" with the specific reason
(which SG rule or route blocked the path).

### How does private EC2 access the internet without a public IP?

The private EC2 sends traffic to its default gateway (VPC router).
The route table has `0.0.0.0/0 → NAT Gateway`.
The VPC router forwards to the NAT Gateway in the public subnet.
NAT replaces the source IP (private EC2) with its own Elastic IP.
The packet exits through the Internet Gateway.
Return traffic arrives at the NAT Gateway, which translates back to the private EC2 IP.
The private EC2 never needs a public IP.

---

## Cost Considerations

Approximate monthly cost for this lab (ap-south-1, running 24/7):

| Resource              | ~Cost/Month |
|----------------------|------------|
| NAT Gateway           | ~$40       |
| ALB                   | ~$20       |
| RDS db.t3.micro       | ~$15       |
| 2× EC2 t3.micro       | ~$15       |
| Elastic IP (in use)   | Free       |
| CloudWatch Flow Logs  | ~$1        |
| **Total**             | **~$90**   |

> **Stop billing immediately when done:** `make destroy`

For short experiments, use `terraform destroy` between sessions.
The most expensive component is NAT Gateway, which charges per hour AND per GB.

---

## Cleanup

```bash
make destroy
# OR
cd terraform/environments/dev
terraform destroy
```

**Order matters:** Terraform handles dependencies automatically, but note:
- RDS must be destroyed before DB subnet group
- NAT Gateway must be destroyed before EIP release
- Terraform handles all of this correctly

---

## Repository Structure

```
.
├── terraform/
│   ├── modules/           # Reusable modules
│   │   ├── vpc/           # VPC, IGW, Flow Logs
│   │   ├── subnets/       # All subnet tiers
│   │   ├── routes/        # Route tables, NAT Gateway, associations
│   │   ├── security-groups/ # SGs and NACLs
│   │   ├── alb/           # ALB, listeners, target group
│   │   ├── application/   # EC2, IAM, launch template
│   │   ├── rds/           # RDS, Secrets Manager, DB subnet group
│   │   └── dns/           # Route 53, ACM
│   └── environments/dev/  # Root configuration
│
├── application/src/app.py # FastAPI app with /health, /az, /db-check, /egress-check
├── scripts/               # Validation and test scripts
├── docs/                  # Architecture, CIDR, routing, security, troubleshooting
├── diagrams/              # Mermaid network diagrams
├── screenshots/           # Real AWS console screenshots (captured after deploy)
├── .github/workflows/     # Terraform CI (fmt, validate, Trivy, tflint)
├── Makefile               # Common operations
└── README.md
```

---

## Lessons Learned

1. **Route tables and security groups are independent controls.** A misconfigured
   route can strand traffic before it reaches any SG. Always check both layers.

2. **NAT failure is invisible to inbound traffic.** The ALB→App path uses VPC-local
   routing and is unaffected when NAT goes down. This makes NAT failures subtle.

3. **NACL ephemeral ports are the most common misconfiguration.** Forgetting to
   allow 1024-65535 outbound on the sending side or inbound on the receiving side
   breaks all TCP connections silently.

4. **Target group health checks are the first failure indicator.** When the
   application is unreachable, check target health BEFORE investigating DNS or ALB.
   The health check reason pinpoints whether the issue is connectivity (SG/route)
   or application behavior (wrong path/status code).

5. **SG-to-SG references are safer than CIDR-based rules.** Referencing the ALB's
   SG ID in the App SG ensures only ALB ENIs can reach the app port, regardless of
   what IP range the ALB happens to use.

6. **Reachability Analyzer saves time.** Instead of making changes and waiting, use
   Reachability Analyzer to immediately understand why a path is blocked.
