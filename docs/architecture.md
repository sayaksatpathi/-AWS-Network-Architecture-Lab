# Architecture Reference

## Overview

A multi-tier AWS VPC isolating public, application, and database layers
across two Availability Zones.

## Component Inventory

| Component | Type | Location | Purpose |
|-----------|------|----------|---------|
| VPC | aws_vpc | us/region | Network boundary |
| Internet Gateway | aws_internet_gateway | VPC | Inbound/outbound internet |
| NAT Gateway | aws_nat_gateway | Public Subnet A | Private subnet egress |
| Elastic IP | aws_eip | Public Subnet A | NAT Gateway's public IP |
| Application Load Balancer | aws_lb | Public Subnets A+B | Internet-facing ingress |
| ALB Target Group | aws_lb_target_group | - | Healthy target tracking |
| EC2 Launch Template | aws_launch_template | - | App instance configuration |
| EC2 Instances | aws_instance | Private App Subnets | Application hosts |
| RDS Instance | aws_db_instance | Private DB Subnets | PostgreSQL database |
| DB Subnet Group | aws_db_subnet_group | - | RDS subnet binding |
| Secrets Manager | aws_secretsmanager_secret | - | RDS credentials |
| ACM Certificate | aws_acm_certificate | - | TLS termination at ALB |
| Route 53 Record | aws_route53_record | - | DNS alias to ALB |

## Subnet Layout

| Subnet | CIDR | AZ | Route Table | Internet Access |
|--------|------|----|-------------|----------------|
| Public A | 10.0.1.0/24 | AZ-a | Public RT | IGW (full) |
| Public B | 10.0.2.0/24 | AZ-b | Public RT | IGW (full) |
| Private App A | 10.0.11.0/24 | AZ-a | Private App RT | NAT (outbound only) |
| Private App B | 10.0.12.0/24 | AZ-b | Private App RT | NAT (outbound only) |
| Private DB A | 10.0.21.0/24 | AZ-a | Private DB RT | None |
| Private DB B | 10.0.22.0/24 | AZ-b | Private DB RT | None |

## Security Chain

```
Internet
  → ALB SG (TCP 443/80 from 0.0.0.0/0)
  → App SG (TCP 8080 from ALB SG ID)
  → DB SG (TCP 5432 from App SG ID)
```

The chain uses SG-to-SG references (not CIDR), so only ALB ENIs can
reach the app port, and only app ENIs can reach the database port.

## IAM Roles

The EC2 application instances have a role with:
- `AmazonSSMManagedInstanceCore` — enables SSM Session Manager access
- `CloudWatchAgentServerPolicy` — enables CloudWatch agent log shipping

No SSH key pair is required. Access is via SSM Session Manager:
```bash
aws ssm start-session --target <instance-id>
```

## VPC Flow Logs

When `enable_flow_logs = true`, all VPC traffic is logged to CloudWatch
under the log group `/aws/vpc/<project-name>-<env>-flow-logs`.

Flow log format includes: account-id, vpc-id, subnet-id, instance-id,
srcaddr, dstaddr, srcport, dstport, protocol, packets, bytes, action.

## High Availability Design

| Component | HA Strategy |
|-----------|------------|
| ALB | Spans both AZs, routes around failures |
| EC2 | One instance per AZ (configurable count) |
| NAT Gateway | Single AZ-a (lab design; production would deploy per-AZ) |
| RDS | DB subnet group across both AZs; Multi-AZ optional |

Note: The NAT Gateway is in a single AZ for cost reasons in this lab.
In a production deployment, deploy one NAT Gateway per AZ for resilience.
