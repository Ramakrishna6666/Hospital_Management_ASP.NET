# AWS ECS Deployment Guide

## Prerequisites
- AWS Account with appropriate permissions
- AWS CLI configured
- Docker installed (for building images)
- ECR repository created

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Application Load Balancer             │
│                         (Port 80/443)                        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                      ECS Service                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Task 1     │  │   Task 2     │  │   Task 3     │      │
│  │  (Container) │  │  (Container) │  │  (Container) │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└────────────────────────┬────────────────────────────────────┘
                         │
          ┌──────────────┴──────────────┐
          ▼                              ▼
┌──────────────────┐          ┌──────────────────┐
│  ElastiCache     │          │   RDS SQL Server │
│  (Redis)         │          │                  │
└──────────────────┘          └──────────────────┘
```

## Step 1: Create ElastiCache Redis Cluster

```bash
# Create Redis subnet group
aws elasticache create-cache-subnet-group \
  --cache-subnet-group-name clinic-redis-subnet \
  --cache-subnet-group-description "Subnet group for clinic Redis" \
  --subnet-ids subnet-xxxxx subnet-yyyyy

# Create Redis cluster
aws elasticache create-replication-group \
  --replication-group-id clinic-redis \
  --replication-group-description "Redis for clinic session state" \
  --engine redis \
  --cache-node-type cache.t3.micro \
  --num-cache-clusters 2 \
  --automatic-failover-enabled \
  --cache-subnet-group-name clinic-redis-subnet \
  --security-group-ids sg-xxxxx \
  --at-rest-encryption-enabled \
  --transit-encryption-enabled \
  --auth-token "YourSecureAuthToken123!"

# Get Redis endpoint
aws elasticache describe-replication-groups \
  --replication-group-id clinic-redis \
  --query 'ReplicationGroups[0].ConfigurationEndpoint.Address' \
  --output text
```

## Step 2: Create RDS SQL Server Instance

```bash
# Create DB subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name clinic-db-subnet \
  --db-subnet-group-description "Subnet group for clinic database" \
  --subnet-ids subnet-xxxxx subnet-yyyyy

# Create SQL Server instance
aws rds create-db-instance \
  --db-instance-identifier clinic-sqlserver \
  --db-instance-class db.t3.small \
  --engine sqlserver-ex \
  --master-username admin \
  --master-user-password "YourSecurePassword123!" \
  --allocated-storage 20 \
  --db-subnet-group-name clinic-db-subnet \
  --vpc-security-group-ids sg-xxxxx \
  --backup-retention-period 7 \
  --storage-encrypted

# Get DB endpoint
aws rds describe-db-instances \
  --db-instance-identifier clinic-sqlserver \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text
```

## Step 3: Build and Push Docker Image

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Build image
docker build -t clinic-management-system .

# Tag image
docker tag clinic-management-system:latest \
  <account-id>.dkr.ecr.us-east-1.amazonaws.com/clinic-management-system:latest

# Push to ECR
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/clinic-management-system:latest
```

## Step 4: Create ECS Task Definition

Create `task-definition.json`:

```json
{
  "family": "clinic-management-system",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "arn:aws:iam::<account-id>:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::<account-id>:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "clinic-webapp",
      "image": "<account-id>.dkr.ecr.us-east-1.amazonaws.com/clinic-management-system:latest",
      "portMappings": [
        {
          "containerPort": 80,
          "protocol": "tcp"
        }
      ],
      "essential": true,
      "environment": [],
      "secrets": [
        {
          "name": "REDIS_CONNECTION_STRING",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:<account-id>:secret:clinic/redis-connection"
        },
        {
          "name": "DB_CONNECTION_STRING",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:<account-id>:secret:clinic/db-connection"
        }
      ],
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "powershell -command \"try { $response = Invoke-WebRequest -Uri http://localhost/Helpers/HealthCheckHandler.ashx -UseBasicParsing; if ($response.StatusCode -eq 200) { exit 0 } else { exit 1 } } catch { exit 1 }\""
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      },
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/clinic-management-system",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

Register the task definition:

```bash
aws ecs register-task-definition --cli-input-json file://task-definition.json
```

## Step 5: Store Secrets in AWS Secrets Manager

```bash
# Store Redis connection string
aws secretsmanager create-secret \
  --name clinic/redis-connection \
  --description "Redis connection string for clinic app" \
  --secret-string "<redis-endpoint>:6379,password=YourSecureAuthToken123!,ssl=True,abortConnect=False"

# Store DB connection string
aws secretsmanager create-secret \
  --name clinic/db-connection \
  --description "Database connection string for clinic app" \
  --secret-string "Server=<db-endpoint>,1433;Database=DBProject;User Id=admin;Password=YourSecurePassword123!;Encrypt=True;TrustServerCertificate=False;"
```

## Step 6: Create ECS Service

```bash
# Create ECS cluster
aws ecs create-cluster --cluster-name clinic-cluster

# Create Application Load Balancer
aws elbv2 create-load-balancer \
  --name clinic-alb \
  --subnets subnet-xxxxx subnet-yyyyy \
  --security-groups sg-xxxxx \
  --scheme internet-facing \
  --type application

# Create target group
aws elbv2 create-target-group \
  --name clinic-tg \
  --protocol HTTP \
  --port 80 \
  --vpc-id vpc-xxxxx \
  --target-type ip \
  --health-check-enabled \
  --health-check-path /Helpers/HealthCheckHandler.ashx \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3

# Create listener
aws elbv2 create-listener \
  --load-balancer-arn <alb-arn> \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=<target-group-arn>

# Create ECS service
aws ecs create-service \
  --cluster clinic-cluster \
  --service-name clinic-service \
  --task-definition clinic-management-system \
  --desired-count 2 \
  --launch-type FARGATE \
  --platform-version LATEST \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxxxx,subnet-yyyyy],securityGroups=[sg-xxxxx],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=<target-group-arn>,containerName=clinic-webapp,containerPort=80" \
  --health-check-grace-period-seconds 60
```

## Step 7: Configure Auto Scaling

```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/clinic-cluster/clinic-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10

# Create scaling policy
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/clinic-cluster/clinic-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name clinic-cpu-scaling \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration file://scaling-policy.json
```

Create `scaling-policy.json`:

```json
{
  "TargetValue": 70.0,
  "PredefinedMetricSpecification": {
    "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
  },
  "ScaleInCooldown": 300,
  "ScaleOutCooldown": 60
}
```

## Step 8: Configure CloudWatch Alarms

```bash
# Create alarm for high CPU
aws cloudwatch put-metric-alarm \
  --alarm-name clinic-high-cpu \
  --alarm-description "Alert when CPU exceeds 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=ServiceName,Value=clinic-service Name=ClusterName,Value=clinic-cluster

# Create alarm for unhealthy targets
aws cloudwatch put-metric-alarm \
  --alarm-name clinic-unhealthy-targets \
  --alarm-description "Alert when targets are unhealthy" \
  --metric-name UnHealthyHostCount \
  --namespace AWS/ApplicationELB \
  --statistic Average \
  --period 60 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 2 \
  --dimensions Name=TargetGroup,Value=<target-group-name> Name=LoadBalancer,Value=<alb-name>
```

## Step 9: Verify Deployment

```bash
# Check service status
aws ecs describe-services \
  --cluster clinic-cluster \
  --services clinic-service

# Check task status
aws ecs list-tasks --cluster clinic-cluster --service-name clinic-service

# Get ALB DNS name
aws elbv2 describe-load-balancers \
  --names clinic-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text

# Test health check
curl http://<alb-dns-name>/Helpers/HealthCheckHandler.ashx
```

## Security Best Practices

1. **Network Security:**
   - Place ECS tasks in private subnets
   - Use NAT Gateway for outbound internet access
   - Restrict security groups to minimum required ports

2. **Secrets Management:**
   - Never hardcode credentials
   - Use AWS Secrets Manager for all sensitive data
   - Rotate secrets regularly

3. **IAM Roles:**
   - Use least privilege principle
   - Separate execution role and task role
   - Enable CloudTrail for audit logging

4. **Encryption:**
   - Enable encryption at rest for RDS and ElastiCache
   - Enable encryption in transit (SSL/TLS)
   - Use AWS KMS for key management

## Monitoring and Logging

1. **CloudWatch Logs:**
   - All container logs are sent to CloudWatch Logs
   - Log group: `/ecs/clinic-management-system`

2. **CloudWatch Metrics:**
   - Monitor CPU, memory, network utilization
   - Track health check success rate
   - Monitor Redis and RDS metrics

3. **X-Ray (Optional):**
   - Enable AWS X-Ray for distributed tracing
   - Add X-Ray daemon as sidecar container

## Cost Optimization

1. **Right-sizing:**
   - Start with smaller instance types
   - Monitor and adjust based on actual usage

2. **Reserved Capacity:**
   - Consider Savings Plans for predictable workloads
   - Use Spot instances for non-critical tasks

3. **Auto Scaling:**
   - Scale down during off-peak hours
   - Use target tracking for efficient scaling

## Troubleshooting

### Tasks Failing Health Checks
- Check CloudWatch Logs for application errors
- Verify health check endpoint is accessible
- Increase health check grace period if needed

### Connection Issues to Redis/RDS
- Verify security group rules
- Check network ACLs
- Ensure secrets are correctly configured

### High Latency
- Check Redis connection pool settings
- Monitor database query performance
- Consider adding read replicas

## Rollback Procedure

```bash
# Update service to previous task definition
aws ecs update-service \
  --cluster clinic-cluster \
  --service clinic-service \
  --task-definition clinic-management-system:<previous-revision>

# Monitor rollback
aws ecs describe-services \
  --cluster clinic-cluster \
  --services clinic-service
```

## Maintenance

### Updating the Application

```bash
# Build and push new image
docker build -t clinic-management-system:v2 .
docker tag clinic-management-system:v2 <account-id>.dkr.ecr.us-east-1.amazonaws.com/clinic-management-system:v2
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/clinic-management-system:v2

# Register new task definition with new image
# Update task-definition.json with new image tag
aws ecs register-task-definition --cli-input-json file://task-definition.json

# Update service (rolling deployment)
aws ecs update-service \
  --cluster clinic-cluster \
  --service clinic-service \
  --task-definition clinic-management-system:<new-revision>
```

### Database Migrations

```bash
# Connect to RDS instance
sqlcmd -S <db-endpoint> -U admin -P <password>

# Run migration scripts
# Or use ECS task to run migrations before deployment
```

## Support and Resources

- AWS ECS Documentation: https://docs.aws.amazon.com/ecs/
- AWS ElastiCache Documentation: https://docs.aws.amazon.com/elasticache/
- AWS RDS Documentation: https://docs.aws.amazon.com/rds/
