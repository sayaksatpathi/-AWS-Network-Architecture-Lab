# DNS and TLS Reference

## Architecture Overview

DNS and TLS are optional in this lab, controlled by variables:

```hcl
create_dns  = false  # disable: use ALB DNS directly
create_dns  = true   # enable: create Route 53 alias record

create_tls  = false  # disable: HTTP only
create_tls  = true   # enable: ACM certificate + HTTPS listener
```

When both are false, the application is fully functional at:
```
http://<alb-dns-name>/
```

All network behavior (routing, NAT, SGs, NACLs) is identical
whether DNS/TLS are enabled or not.

---

## DNS (Route 53)

### What Gets Created

When `create_dns = true`:

1. **Route 53 A record** (alias type) pointing to the ALB
   - Name: `<subdomain>.<domain_name>` (e.g. `app.example.com`)
   - Type: ALIAS to ALB DNS name
   - Alias target: ALB DNS name + hosted zone ID

### Alias vs CNAME

Route 53 alias records are AWS-specific. Unlike a CNAME:
- Alias records can point to an ALB's DNS name at the zone apex
- Alias records resolve to the ALB's current IP addresses
- Alias records do not incur per-query charges (CNAMEs do)
- Alias records are aware of ALB health — they automatically
  remove IPs for unhealthy AZs

### Hosted Zone Requirement

You must provide the hosted zone ID for a domain you control in Route 53.
The lab does not create the hosted zone — it only creates records within it.

---

## TLS (ACM)

### What Gets Created

When `create_tls = true`:

1. **ACM Certificate** for `<subdomain>.<domain_name>`
2. **DNS validation records** in the Route 53 hosted zone
3. **HTTPS listener** on the ALB (TCP 443) with the certificate
4. **HTTP listener** redirects to HTTPS (instead of forwarding directly)

### Certificate Validation

ACM uses DNS validation: it creates a CNAME record in your Route 53
zone. When Route 53 resolves that CNAME correctly, ACM marks the
certificate as issued. This typically takes 2–5 minutes.

### TLS Policy

The HTTPS listener uses `ELBSecurityPolicy-TLS13-1-2-2021-06` which:
- Supports TLS 1.2 and TLS 1.3
- Supports modern cipher suites
- Rejects TLS 1.0 and 1.1 (deprecated)

### Where TLS Terminates

TLS terminates at the ALB, not at the application:
- Client → ALB: HTTPS (TLS 1.2/1.3)
- ALB → App EC2: HTTP (plain, VPC-internal)

This is the standard pattern for AWS workloads. The traffic from
ALB to the application is VPC-internal and considered trusted.
The application does not need a certificate.

---

## Troubleshooting DNS

```bash
# Resolve the custom hostname
dig app.example.com +short

# What does the ALB DNS resolve to?
dig <alb-dns-name> +short

# Both should return the same IPs
# If app.example.com returns NXDOMAIN: check Route 53 record
# If app.example.com returns wrong IP: check alias target in Route 53

# Check Route 53 records
aws route53 list-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --query "ResourceRecordSets[?Name=='app.example.com.']"
```

## Troubleshooting TLS

```bash
# See what certificate the ALB is presenting
openssl s_client -connect <alb-dns>:443 \
  -servername app.example.com 2>/dev/null \
  | openssl x509 -noout -subject -dates

# Verbose curl with TLS details
curl -v https://app.example.com/health 2>&1 | grep -i "ssl\|tls\|cert\|issuer"

# Check ACM certificate status
aws acm describe-certificate --certificate-arn <arn> \
  --query "Certificate.Status"
# → "ISSUED" is good; "PENDING_VALIDATION" means DNS record not yet propagated
```

## Without DNS/TLS

The application is still fully demonstrable via the ALB DNS name:

```bash
# Get ALB DNS
ALB_DNS=$(terraform -chdir=terraform/environments/dev output -raw alb_dns_name)

# Test all endpoints
curl http://$ALB_DNS/health
curl http://$ALB_DNS/az
curl http://$ALB_DNS/egress-check
curl http://$ALB_DNS/db-check
```

All networking, routing, NAT, and security concepts are demonstrated
whether or not DNS and TLS are configured.
