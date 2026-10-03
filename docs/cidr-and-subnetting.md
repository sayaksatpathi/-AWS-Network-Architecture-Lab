# CIDR and Subnetting

## VPC CIDR Selection: 10.0.0.0/16

`10.0.0.0/16` provides 65,536 IP addresses in the RFC-1918 private range.

**Why /16?**
- Large enough to never run out during development or small production workloads
- Small enough to avoid accidentally overlapping with on-premises or peered VPC ranges
- Splits cleanly into /24 subnets (256 addresses each)

## Subnet Design

### Tiers and their CIDRs

| Subnet              | CIDR           | AZ      | Tier        | Internet Route? |
|--------------------|----------------|---------|-------------|-----------------|
| Public Subnet A     | 10.0.1.0/24    | AZ-a    | public      | → IGW           |
| Public Subnet B     | 10.0.2.0/24    | AZ-b    | public      | → IGW           |
| Private App A       | 10.0.11.0/24   | AZ-a    | private-app | → NAT           |
| Private App B       | 10.0.12.0/24   | AZ-b    | private-app | → NAT           |
| Private DB A        | 10.0.21.0/24   | AZ-a    | private-db  | None            |
| Private DB B        | 10.0.22.0/24   | AZ-b    | private-db  | None            |

### Why /24 per subnet?

256 addresses per subnet (minus 5 reserved by AWS = 251 usable).  
Enough for any realistic lab or small production workload.  
Easy to read: the third octet identifies the tier (1x=public, 11-12=app, 21-22=db).

### Octet-based tier separation

The third octet encodes the tier:
- `1.x` and `2.x` → public
- `11.x` and `12.x` → private app
- `21.x` and `22.x` → private db

This makes CIDR-based NACL rules and security group rules readable at a glance.

### Address Space Layout

```
10.0.0.0/16  — VPC
  ├── 10.0.1.0/24   — Public Subnet A (AZ-a)
  ├── 10.0.2.0/24   — Public Subnet B (AZ-b)
  ├── 10.0.3.0/24   — (reserved for future public use)
  │   ...
  ├── 10.0.11.0/24  — Private App A (AZ-a)
  ├── 10.0.12.0/24  — Private App B (AZ-b)
  │   ...
  ├── 10.0.21.0/24  — Private DB A (AZ-a)
  └── 10.0.22.0/24  — Private DB B (AZ-b)
```

### AWS Reserved Addresses (per /24 subnet)

| Address        | Reserved for       |
|---------------|-------------------|
| 10.0.x.0      | Network address   |
| 10.0.x.1      | VPC router        |
| 10.0.x.2      | DNS server        |
| 10.0.x.3      | Future use (AWS)  |
| 10.0.x.255    | Broadcast (AWS)   |

Usable addresses per /24: 256 − 5 = **251**

## Subnetting Math

### /16 → /24 calculation

```
/16 = 16 fixed bits, 16 host bits = 2^16 = 65,536 addresses
/24 = 24 fixed bits, 8 host bits  = 2^8  = 256 addresses
Number of /24 subnets in a /16 = 2^(24-16) = 256 subnets
```

### What makes a subnet "public"?

The subnet CIDR alone does not make a subnet public or private.
A subnet is public **because its associated route table contains a route to an Internet Gateway**.
Remove that route and the subnet becomes effectively private — even if it has
`map_public_ip_on_launch = true`.

This architecture makes the separation explicit by:
1. Creating separate route tables for each tier
2. Explicitly associating every subnet with its intended route table
3. Never relying on the VPC's default (main) route table
