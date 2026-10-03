# Operations Reference

## Accessing Application Instances

EC2 instances are in private subnets with no public IP. Access via SSM:

```bash
# List app instances
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=aws-network-lab-dev-app-*" \
  --query "Reservations[*].Instances[*].[InstanceId,PrivateIpAddress,State.Name]" \
  --output table

# Start session
aws ssm start-session --target i-0123456789abcdef0

# Inside the instance:
systemctl status network-lab-app    # check app status
journalctl -u network-lab-app -f    # tail app logs
curl localhost:8080/health          # direct health check
```

## Application Management

```bash
# Restart the application
sudo systemctl restart network-lab-app

# Check service logs
sudo journalctl -u network-lab-app --no-pager -n 50

# View the application code
cat /opt/app/main.py

# Test locally (inside instance)
curl -s localhost:8080/
curl -s localhost:8080/health
curl -s localhost:8080/az
curl -s localhost:8080/egress-check
```

## Retrieving Database Credentials

Credentials are stored in Secrets Manager:

```bash
# Get secret ARN
SECRET_ARN=$(terraform -chdir=terraform/environments/dev output -raw db_secret_arn)

# Retrieve secret value
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --query SecretString \
  --output text | python3 -m json.tool
```

The secret contains: `host`, `port`, `username`, `password`, `engine`.

## Monitoring

### Target Group Health

```bash
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName,'aws-network-lab')].LoadBalancerArn" \
  --output text)

TG_ARN=$(aws elbv2 describe-target-groups \
  --load-balancer-arn "$ALB_ARN" \
  --query "TargetGroups[0].TargetGroupArn" --output text)

aws elbv2 describe-target-health --target-group-arn "$TG_ARN"
```

### VPC Flow Logs

```bash
LOG_GROUP="/aws/vpc/aws-network-lab-dev-flow-logs"

# Recent REJECT entries (blocked traffic)
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --filter-pattern "REJECT" \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --query "events[*].message"
```

### NAT Gateway Metrics

```bash
# NAT Gateway ID
NAT_GW=$(aws ec2 describe-nat-gateways \
  --filter "Name=state,Values=available" \
  --query "NatGateways[0].NatGatewayId" --output text)

# Bytes processed in last hour
aws cloudwatch get-metric-statistics \
  --namespace AWS/NATGateway \
  --metric-name BytesOutToDestination \
  --dimensions Name=NatGatewayId,Value="$NAT_GW" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum
```

## Terraform Operations

```bash
# Plan with no changes expected
terraform -chdir=terraform/environments/dev plan

# Apply specific module (e.g., after changing SG rules)
terraform -chdir=terraform/environments/dev apply -target=module.security_groups

# Show current state
terraform -chdir=terraform/environments/dev show

# List all resources
terraform -chdir=terraform/environments/dev state list

# Inspect a specific resource
terraform -chdir=terraform/environments/dev state show module.vpc.aws_vpc.main
```

## Cost Management

The most expensive components are NAT Gateway and RDS.

```bash
# Destroy everything when done
make destroy
# or
terraform -chdir=terraform/environments/dev destroy
```

Approximate costs if left running (ap-south-1):
- NAT Gateway: ~$0.045/hr + $0.045/GB data processed
- ALB: ~$0.008/hr + LCU charges
- RDS db.t3.micro: ~$0.020/hr
- EC2 t3.micro: ~$0.010/hr each

Total: ~$0.10/hr (~$75/month) if running 24/7.

For experiments: destroy between sessions. The entire environment
rebuilds in ~8 minutes.

## Cleanup Order

Terraform handles dependency ordering automatically. Destroy in one command:

```bash
terraform -chdir=terraform/environments/dev destroy -auto-approve
```

Manual cleanup order (if needed):
1. EC2 instances
2. ALB
3. RDS (wait for deletion)
4. NAT Gateway
5. Secrets Manager secret
6. DB subnet group
7. Security groups
8. Route tables (disassociate first)
9. Subnets
10. Internet Gateway (detach first)
11. VPC
12. EIP (release)
13. CloudWatch log group
