# Security Model

## Security Group vs Network ACL

| Feature          | Security Group            | Network ACL                    |
|-----------------|--------------------------|-------------------------------|
| Level            | Resource / ENI            | Subnet                         |
| State            | **Stateful**              | **Stateless**                  |
| Rules            | Allow only                | Allow and Deny                 |
| Return traffic   | Automatic                 | Must explicitly allow          |
| Evaluation order | All rules evaluated       | Ordered (lowest rule first)    |
| Scope            | One resource at a time    | All resources in subnet        |

### Why does stateful vs stateless matter?

**Security Group (stateful):**  
If you allow TCP 443 inbound, the return traffic (source ephemeral port) is
automatically allowed outbound. No outbound rule needed for the response.

**NACL (stateless):**  
If you allow TCP 443 inbound, you must ALSO explicitly allow the return
traffic outbound on ephemeral ports (1024–65535). Forgetting ephemeral ports
is the most common NACL misconfiguration.

---

## Security Group Design

### Chain of SG References

```
Internet
   ↓ TCP 443
[ ALB SG ]  — allows 443/80 from 0.0.0.0/0
   ↓ TCP 8080
[ App SG ]  — allows 8080 ONLY from ALB SG ID
   ↓ TCP 5432
[ DB SG ]   — allows 5432 ONLY from App SG ID
```

**Why SG-to-SG references instead of CIDRs?**

If the App SG allowed `10.0.0.0/16 → port 8080`, then any resource in the
VPC could reach the application — not just the ALB. By referencing the ALB SG
specifically, only ENIs that are members of the ALB SG can reach the app port.
This is more precise and doesn't require updating if subnets change.

### ALB Security Group

```
Inbound:
  TCP 443  from 0.0.0.0/0  (HTTPS)
  TCP 80   from 0.0.0.0/0  (HTTP → redirect to HTTPS)
Outbound:
  All traffic (to reach app tier)
```

### Application Security Group

```
Inbound:
  TCP 8080 from ALB Security Group ID
Outbound:
  All traffic (for NAT egress and RDS access)
```

### Database Security Group

```
Inbound:
  TCP 5432 from App Security Group ID (PostgreSQL)
Outbound:
  All traffic (minimal — could be restricted to VPC CIDR)
```

---

## Network ACL Strategy

NACLs provide a subnet-level defense layer. This architecture uses them
to be explicit about what traffic should flow between tiers.

### Public Subnet NACL

```
Inbound:
  100: TCP 443  from 0.0.0.0/0  ALLOW
  110: TCP 80   from 0.0.0.0/0  ALLOW
  900: TCP 1024-65535 from 0.0.0.0/0  ALLOW  (ephemeral — return traffic)

Outbound:
  100: TCP 443  to 0.0.0.0/0    ALLOW
  110: TCP 80   to 0.0.0.0/0    ALLOW
  120: TCP 8080 to VPC CIDR     ALLOW  (ALB → app instances)
  900: TCP 1024-65535 to 0.0.0.0/0  ALLOW  (ephemeral)
```

### Private App Subnet NACL

```
Inbound:
  100: TCP 8080 from VPC CIDR   ALLOW  (from ALB)
  900: TCP 1024-65535 from 0.0.0.0/0  ALLOW  (return from NAT/DB)

Outbound:
  100: TCP 443  to 0.0.0.0/0    ALLOW  (HTTPS egress via NAT)
  110: TCP 5432 to VPC CIDR     ALLOW  (to DB)
  900: TCP 1024-65535 to 0.0.0.0/0  ALLOW  (responses to ALB)
```

### Private DB Subnet NACL

```
Inbound:
  100: TCP 5432 from VPC CIDR   ALLOW  (from app tier)

Outbound:
  900: TCP 1024-65535 to 0.0.0.0/0  ALLOW  (responses to app)
```

Note: The DB NACL does NOT need outbound on port 5432 — responses use
ephemeral ports (1024-65535), not the database port.

---

## What "Private" Actually Means

A resource is private when ALL of the following are true:

1. It has no public IP address
2. Its subnet's route table has no route to an Internet Gateway  
   (route to NAT is fine — NAT is outbound-only)
3. Its security group allows inbound traffic only from trusted sources
4. The subnet's NACL restricts inbound traffic appropriately

A resource with a public IP but a restrictive SG is NOT truly private —
it is reachable from the internet if the SG is misconfigured.
A private IP with no IGW route is private even with a permissive SG,
because there is no internet path to reach it.

This lab achieves privacy through both the routing layer (no IGW route
in private subnets) AND the security layer (SG allows only trusted sources).
Defense in depth.
