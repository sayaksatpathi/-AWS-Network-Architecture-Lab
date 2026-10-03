# Troubleshooting Lab

Six intentional failure scenarios demonstrating real AWS network diagnosis.
Each scenario follows the same structure: introduce failure → observe symptom → diagnose → fix → verify.

---

## Scenario 1 — Security Group: ALB → Application Rule Removed

### Setup

Remove the inbound rule from the App SG that allows traffic from the ALB SG.

```bash
# Get App SG ID
APP_SG=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=aws-network-lab-dev-app-sg" \
  --query "SecurityGroups[0].GroupId" --output text)

ALB_SG=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=aws-network-lab-dev-alb-sg" \
  --query "SecurityGroups[0].GroupId" --output text)

# Remove the rule (introduce failure)
aws ec2 revoke-security-group-ingress \
  --group-id "$APP_SG" \
  --protocol tcp --port 8080 \
  --source-group "$ALB_SG"
```

### Observed Symptom

```
curl http://<alb-dns>/health
→ 502 Bad Gateway or 503 Service Unavailable

AWS Console → EC2 → Target Groups → aws-network-lab-dev-app-tg
→ Targets show: unhealthy (Health check failed)
```

ALB can be reached (DNS resolves, port 443/80 open) but all targets become
unhealthy. ALB has no healthy targets to route to, so it returns 5xx.

### Diagnosis

```bash
# 1. Check target health
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName,'aws-network-lab')].LoadBalancerArn" \
  --output text)

TG_ARN=$(aws elbv2 describe-target-groups \
  --load-balancer-arn "$ALB_ARN" \
  --query "TargetGroups[0].TargetGroupArn" --output text)

aws elbv2 describe-target-health --target-group-arn "$TG_ARN"
# → State: unhealthy, Reason: "Health checks failed"

# 2. Inspect App SG rules — notice the ALB rule is missing
aws ec2 describe-security-groups --group-ids "$APP_SG" \
  --query "SecurityGroups[0].IpPermissions"
# → TCP 8080 from ALB SG is absent

# 3. Confirm via VPC Flow Logs (if enabled)
# Look for REJECT on port 8080 from ALB IP range toward app instance IP
# aws logs filter-log-events --log-group-name /aws/vpc/aws-network-lab-dev-flow-logs \
#   --filter-pattern "REJECT"
```

### Root Cause

The App SG has no inbound rule allowing the ALB SG on port 8080. When the ALB
health-check probe reaches the EC2 ENI, the security group drops the packet
(stateful deny — the packet never reaches the application process).

### Fix

```bash
# Restore the rule
aws ec2 authorize-security-group-ingress \
  --group-id "$APP_SG" \
  --protocol tcp --port 8080 \
  --source-group "$ALB_SG"
```

Or via Terraform:
```bash
terraform -chdir=terraform/environments/dev apply -target=module.security_groups
```

### Verification

```bash
# Wait 30–60 seconds for health checks to cycle
aws elbv2 describe-target-health --target-group-arn "$TG_ARN"
# → State: healthy

curl http://<alb-dns>/health
# → {"status":"healthy"}
```

### Lesson Learned

Security group rules are instance-level stateful firewalls. When the ALB health
check cannot reach the target, the target is marked unhealthy and removed from
rotation. The failure is visible at the target group, not at DNS or the ALB
listener. Distinguishing "ALB unreachable" from "targets unhealthy" is the
first diagnostic step.

---

## Scenario 2 — Route Table: NAT Route Removed

### Setup

Remove the `0.0.0.0/0 → NAT Gateway` route from the private application route table.

```bash
PRIV_RT=$(aws ec2 describe-route-tables \
  --filters "Name=tag:Tier,Values=private-app" \
  --query "RouteTables[0].RouteTableId" --output text)

NAT_GW=$(aws ec2 describe-nat-gateways \
  --filter "Name=state,Values=available" \
  --query "NatGateways[0].NatGatewayId" --output text)

# Remove the NAT route (introduce failure)
aws ec2 delete-route \
  --route-table-id "$PRIV_RT" \
  --destination-cidr-block "0.0.0.0/0"
```

### Observed Symptom

```
curl http://<alb-dns>/egress-check
→ 503 {"status": "failed", "diagnosis": "Check Private App route table..."}

# But:
curl http://<alb-dns>/health
→ 200 {"status": "healthy"}   # Inbound path unaffected!

curl http://<alb-dns>/db-check
→ 200 {"status": "reachable"} # DB path unaffected (VPC-local)
```

**Key insight:** Only outbound internet egress fails. The ALB→App path and
App→RDS path continue to work because they use the VPC-local route, which
is not affected by the 0.0.0.0/0 NAT route.

### Diagnosis

```bash
# 1. Check route table from an app instance via SSM
aws ssm start-session --target <instance-id>
# (inside instance)
ip route
# → default via 10.0.11.x dev eth0  (or no default route at all)
# → 10.0.0.0/16 via 10.0.11.x dev eth0

curl --max-time 5 https://checkip.amazonaws.com
# → curl: (28) Connection timed out

# 2. Inspect route table
aws ec2 describe-route-tables --route-table-ids "$PRIV_RT" \
  --query "RouteTables[0].Routes"
# → Notice: no entry with DestinationCidrBlock = "0.0.0.0/0"
```

### Root Cause

The private app route table has no default route. Packets destined for
non-VPC IPs have no route and are dropped at the VPC router. There is no
error in the security group or NAT Gateway — the route was simply missing.

### Fix

```bash
aws ec2 create-route \
  --route-table-id "$PRIV_RT" \
  --destination-cidr-block "0.0.0.0/0" \
  --nat-gateway-id "$NAT_GW"
```

### Verification

```bash
curl http://<alb-dns>/egress-check
# → {"status": "success", "public_ip": "13.x.x.x (NAT EIP)"}
```

### Lesson Learned

Route tables and security groups are independent controls. A route failure
affects forwarding decisions; a SG failure affects packet admission at the
endpoint. A route failure can be diagnosed by inspecting the route table —
no need to look at security groups.

---

## Scenario 3 — DNS Failure: Wrong ALB Target

### Setup

Change the Route 53 alias record to point to a non-existent endpoint.

```bash
# This requires a domain. If not configured, simulate by modifying /etc/hosts
# on a test machine:
# echo "1.2.3.4 app.example.com" >> /etc/hosts
# This points the hostname to an unroutable IP.
```

### Observed Symptom

```
curl https://app.example.com/health
→ curl: (6) Could not resolve host   (if record removed)
→ curl: (7) Failed to connect        (if record points to wrong IP)

dig app.example.com
→ Returns wrong IP or NXDOMAIN
```

### Diagnosis

```bash
# 1. Resolve the hostname
dig app.example.com +short
nslookup app.example.com

# 2. Compare to ALB DNS
dig <alb-dns> +short

# 3. Check Route 53 record
aws route53 list-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --query "ResourceRecordSets[?Name=='app.example.com.']"
```

### Distinguishing DNS vs ALB Problems

```
DNS problem symptoms:
  - dig returns NXDOMAIN or wrong IP
  - curl: "Could not resolve host"
  - Problem affects ALL clients regardless of network

ALB problem symptoms:
  - DNS resolves correctly
  - curl reaches ALB (connection established) but gets 4xx/5xx
  - curl http://<alb-dns-directly>/ also fails or returns error
```

### Fix

```bash
# Via Terraform: re-apply the DNS module
terraform -chdir=terraform/environments/dev apply -target=module.dns
```

### Verification

```bash
dig app.example.com +short
# Must resolve to ALB IPs

curl https://app.example.com/health
# → {"status": "healthy"}
```

---

## Scenario 4 — NAT Failure: EIP Disassociated

### Setup

Delete the NAT Gateway or disassociate the Elastic IP.

```bash
# Simulated by deleting the NAT Gateway:
aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_GW"
```

### Observed Symptom

```
Application is still reachable via ALB:
  curl http://<alb-dns>/health → 200

But private egress fails:
  curl http://<alb-dns>/egress-check → 503

Private instances cannot pull updates:
  (via SSM) curl https://amazonaws.com → timeout
```

### Diagnosis

```bash
# 1. Check NAT Gateway state
aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$VPC_ID" \
  --query "NatGateways[*].{ID:NatGatewayId,State:State}"
# → State: deleted or missing

# 2. Check private RT default route
aws ec2 describe-route-tables --route-table-ids "$PRIV_RT" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0']"
# → May show NatGatewayId with blackhole state

# 3. From app instance (via SSM):
traceroute 8.8.8.8
# → Packets stop at first hop (no route available)
```

### Root Cause

The route still exists (pointing to the now-deleted NAT GW) but the gateway
is gone. The route becomes a "blackhole" — packets are forwarded to the route
entry but silently dropped since the NAT GW no longer exists.

### Fix

```bash
# Recreate the NAT Gateway (requires new EIP if the old one was released)
terraform -chdir=terraform/environments/dev apply -target=module.routes
```

---

## Scenario 5 — Target Group: Wrong Health Check Path

### Setup

Change the health check path to a non-existent endpoint.

```bash
TG_ARN=$(aws elbv2 describe-target-groups \
  --query "TargetGroups[?contains(TargetGroupName,'aws-network-lab')].TargetGroupArn" \
  --output text)

# Introduce failure: wrong health check path
aws elbv2 modify-target-group \
  --target-group-arn "$TG_ARN" \
  --health-check-path "/nonexistent"
```

### Observed Symptom

```
# ALB itself is reachable:
curl -I http://<alb-dns>/
→ HTTP/1.1 503 Service Unavailable (no healthy targets)

# Direct check shows targets unhealthy:
aws elbv2 describe-target-health --target-group-arn "$TG_ARN"
→ HealthCheckReason: "Health checks failed with these codes: [404]"
```

### Distinguishing from SG failure

```
SG failure:
  - Health check reason: "Connection refused" or timeout
  - No TCP connection reaches the app
  - App logs show no health check requests

Health check path failure:
  - Health check reason: "404" or wrong status code
  - TCP connection succeeds (security group is fine)
  - App logs SHOW the health check requests returning 404
```

### Diagnosis

```bash
# 1. Check target health reason
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query "TargetHealthDescriptions[0].TargetHealth"
# → {"State": "unhealthy", "Reason": "Target.ResponseCodeMismatch", "Description": "...404..."}

# 2. Check the health check configuration
aws elbv2 describe-target-groups --target-group-arns "$TG_ARN" \
  --query "TargetGroups[0].HealthCheckPath"
# → "/nonexistent"
```

### Fix

```bash
aws elbv2 modify-target-group \
  --target-group-arn "$TG_ARN" \
  --health-check-path "/health"
```

### Verification

```bash
# Wait 30 seconds (2 × health check interval)
aws elbv2 describe-target-health --target-group-arn "$TG_ARN"
# → State: healthy

curl http://<alb-dns>/
# → 200 with application JSON
```

---

## Scenario 6 — TLS Failure: Certificate Mismatch

### Setup

This scenario requires a configured domain and ACM certificate.
To simulate: upload a self-signed certificate that doesn't match the domain.

```bash
# Generate a self-signed cert for wrong-domain.com
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout wrong.key -out wrong.crt \
  -subj "/CN=wrong-domain.com" -days 1

# Import to ACM
WRONG_CERT_ARN=$(aws acm import-certificate \
  --certificate file://wrong.crt \
  --private-key file://wrong.key \
  --query "CertificateArn" --output text)

# Apply wrong cert to HTTPS listener
HTTPS_LISTENER=$(aws elbv2 describe-listeners \
  --load-balancer-arn "$ALB_ARN" \
  --query "Listeners[?Port==\`443\`].ListenerArn" --output text)

aws elbv2 modify-listener \
  --listener-arn "$HTTPS_LISTENER" \
  --certificates "CertificateArn=$WRONG_CERT_ARN"
```

### Observed Symptom

```
curl https://app.example.com/health
→ curl: (60) SSL certificate problem: certificate subject name 'wrong-domain.com'
→ does not match target host name 'app.example.com'

curl -k https://app.example.com/health   # (bypass TLS verification)
→ {"status": "healthy"}   # Application works; only TLS is broken
```

### Diagnosis

```bash
# 1. Inspect the presented certificate
openssl s_client -connect <alb-dns>:443 -servername app.example.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

# Output shows: CN=wrong-domain.com
# Expected: CN=app.example.com

# 2. Check ALB listener certificate
aws elbv2 describe-listeners --listener-arns "$HTTPS_LISTENER" \
  --query "Listeners[0].Certificates"

# 3. Verify the correct certificate
aws acm list-certificates --certificate-statuses ISSUED \
  --query "CertificateSummaryList[?DomainName=='app.example.com']"
```

### Fix

```bash
# Get the correct certificate ARN
CORRECT_CERT=$(aws acm list-certificates \
  --query "CertificateSummaryList[?DomainName=='app.example.com'].CertificateArn" \
  --output text)

# Restore correct certificate
aws elbv2 modify-listener \
  --listener-arn "$HTTPS_LISTENER" \
  --certificates "CertificateArn=$CORRECT_CERT"

# Clean up wrong cert
aws acm delete-certificate --certificate-arn "$WRONG_CERT_ARN"
```

### Verification

```bash
curl https://app.example.com/health
# → {"status": "healthy"}  (no TLS error)

openssl s_client -connect <alb-dns>:443 -servername app.example.com 2>/dev/null \
  | openssl x509 -noout -subject
# → subject=CN=app.example.com
```

---

## AWS Reachability Analyzer

Use Reachability Analyzer to verify network paths without generating traffic.

### ALB → Application Path

```bash
# Find ALB network interface
ALB_ENI=$(aws ec2 describe-network-interfaces \
  --filters "Name=description,Values=*ELB*" "Name=vpc-id,Values=$VPC_ID" \
  --query "NetworkInterfaces[0].NetworkInterfaceId" --output text)

APP_INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=aws-network-lab-dev-app-1" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)

# Create path analysis
ANALYSIS=$(aws ec2 create-network-insights-path \
  --source "$ALB_ENI" \
  --destination "$APP_INSTANCE_ID" \
  --protocol tcp \
  --destination-port 8080 \
  --query "NetworkInsightsPath.NetworkInsightsPathId" --output text)

# Start analysis
aws ec2 start-network-insights-analysis --network-insights-path-id "$ANALYSIS"
# Returns analysis ID — check results in console or via describe-network-insights-analyses
```

Expected result when correct: **"reachable"**
Expected result with SG failure: **"not reachable"** with explanation pointing to the SG rule.
