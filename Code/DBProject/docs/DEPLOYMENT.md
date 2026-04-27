# Clinic Management System - AWS ECS Fargate Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture](#architecture)
4. [Local Development](#local-development)
5. [AWS ECS Fargate Setup](#aws-ecs-fargate-setup)
6. [Building and Pushing Docker Images](#building-and-pushing-docker-images)
7. [Deploying to AWS ECS](#deploying-to-aws-ecs)
8. [Configuration Management](#configuration-management)
9. [Monitoring and Logging](#monitoring-and-logging)
10. [Troubleshooting](#troubleshooting)
11. [Security Considerations](#security-considerations)
12. [Scaling and Performance](#scaling-and-performance)

---

## Overview

This guide provides comprehensive instructions for deploying the Clinic Management System, an ASP.NET Framework 4.5.2 Web Forms application, to AWS ECS Fargate using Windows containers.

### Technology Stack
- **Framework**: ASP.NET Framework 4.5.2
- **Application Type**: Web Forms Application
- **Container Platform**: Windows Server Core LTSC 2019
- **Deployment Target**: AWS ECS Fargate
- **Database**: SQL Server (external)
- **Session State**: Redis (optional, external)

### Key Features
- Multi-stage Docker build for optimized image size
- Health check endpoint for container orchestration
- CloudWatch integration for centralized logging
- Application Load Balancer support
- Auto-scaling capabilities
- Blue/green deployment support

---

## Prerequisites

### Required Software
1. **Docker Desktop for Windows**
   - Version: 4.0 or higher
   - Windows containers enabled
   - Minimum 8GB RAM allocated

2. **AWS CLI**
   - Version: 2.x or higher
   - Configured with appropriate credentials
   ```bash
   aws --version
   aws configure
   ```

3. **Git** (for version control)
   - Version: 2.x or higher

4. **PowerShell** (for Windows scripts)
   - Version: 5.1 or higher

### AWS Account Requirements
1. **IAM Permissions**
   - ECS full access
   - ECR full access
   - CloudWatch Logs write access
   - VPC and networking permissions
   - IAM role creation permissions

2. **AWS Resources**
   - VPC with at least 2 subnets in different availability zones
   - Security groups configured for HTTP/HTTPS traffic
   - NAT Gateway or Internet Gateway for outbound connectivity
   - SQL Server database (RDS or external)
   - Redis instance (ElastiCache or external) - optional

3. **IAM Roles**
   - **ecsTaskExecutionRole**: Allows ECS to pull images and write logs
   - **ecsTaskRole**: Allows tasks to access AWS services (optional)

---

## Architecture

### Container Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                    Application Load Balancer                │
│                         (Port 80/443)                        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                      ECS Fargate Service                     │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Task Definition (Windows)                │  │
│  │  ┌────────────────────────────────────────────────┐  │  │
│  │  │    Clinic Management System Container          │  │  │
│  │  │    - ASP.NET Framework 4.5.2                   │  │  │
│  │  │    - IIS Web Server                            │  │  │
│  │  │    - Port 80                                   │  │  │
│  │  │    - Health Check: /Helpers/HealthCheckHandler │  │  │
│  │  └────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    External Services                         │
│  - SQL Server Database (RDS)                                │
│  - Redis Cache (ElastiCache) - Optional                     │
│  - CloudWatch Logs                                          │
└─────────────────────────────────────────────────────────────┘
```

### Network Architecture
- **VPC**: Isolated network environment
- **Subnets**: Public subnets for Fargate tasks (with public IP assignment)
- **Security Groups**: Control inbound/outbound traffic
- **Load Balancer**: Distributes traffic across tasks
- **Target Group**: Health checks and routing

---

## Local Development

### Building the Docker Image Locally

1. **Navigate to the project directory**:
   ```bash
   cd /path/to/Newtestdotnet/Code/DBProject
   ```

2. **Build the Docker image**:
   ```bash
   docker build -t clinicmanagementsystem:latest .
   ```

3. **Run the container locally**:
   ```bash
   docker run -d -p 8080:80 --name clinic-app clinicmanagementsystem:latest
   ```

4. **Access the application**:
   - Open browser: `http://localhost:8080`
   - Health check: `http://localhost:8080/Helpers/HealthCheckHandler.ashx`

5. **View container logs**:
   ```bash
   docker logs clinic-app
   ```

6. **Stop and remove the container**:
   ```bash
   docker stop clinic-app
   docker rm clinic-app
   ```

### Using Docker Compose

1. **Start the application**:
   ```bash
   docker-compose up -d
   ```

2. **View logs**:
   ```bash
   docker-compose logs -f
   ```

3. **Stop the application**:
   ```bash
   docker-compose down
   ```

---

## AWS ECS Fargate Setup

### Step 1: Create VPC and Networking (if not exists)

1. **Create VPC**:
   ```bash
   aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region us-east-1
   ```

2. **Create Subnets** (at least 2 in different AZs):
   ```bash
   aws ec2 create-subnet --vpc-id vpc-xxxxx --cidr-block 10.0.1.0/24 --availability-zone us-east-1a
   aws ec2 create-subnet --vpc-id vpc-xxxxx --cidr-block 10.0.2.0/24 --availability-zone us-east-1b
   ```

3. **Create Internet Gateway**:
   ```bash
   aws ec2 create-internet-gateway
   aws ec2 attach-internet-gateway --vpc-id vpc-xxxxx --internet-gateway-id igw-xxxxx
   ```

4. **Create Security Group**:
   ```bash
   aws ec2 create-security-group --group-name clinic-sg --description "Security group for Clinic Management System" --vpc-id vpc-xxxxx
   
   # Allow HTTP traffic
   aws ec2 authorize-security-group-ingress --group-id sg-xxxxx --protocol tcp --port 80 --cidr 0.0.0.0/0
   
   # Allow HTTPS traffic (optional)
   aws ec2 authorize-security-group-ingress --group-id sg-xxxxx --protocol tcp --port 443 --cidr 0.0.0.0/0
   ```

### Step 2: Create IAM Roles

1. **Create ECS Task Execution Role**:
   ```bash
   aws iam create-role --role-name ecsTaskExecutionRole --assume-role-policy-document file://trust-policy.json
   aws iam attach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
   ```

   **trust-policy.json**:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Service": "ecs-tasks.amazonaws.com"
         },
         "Action": "sts:AssumeRole"
       }
     ]
   }
   ```

2. **Create ECS Task Role** (optional, for AWS service access):
   ```bash
   aws iam create-role --role-name ecsTaskRole --assume-role-policy-document file://trust-policy.json
   ```

### Step 3: Create CloudWatch Log Group

```bash
aws logs create-log-group --log-group-name /ecs/clinicmanagementsystem --region us-east-1
```

### Step 4: Create ECS Cluster

```bash
aws ecs create-cluster --cluster-name clinic-cluster --region us-east-1
```

---

## Building and Pushing Docker Images

### Option 1: Using AWS ECR

1. **Run the build-push script**:
   
   **Linux/macOS**:
   ```bash
   chmod +x scripts/build-push.sh
   ./scripts/build-push.sh
   ```
   
   **Windows**:
   ```cmd
   scripts\build-push.bat
   ```

2. **Follow the prompts**:
   - Select registry type: `1` (AWS ECR)
   - Enter AWS Region: `us-east-1`
   - Enter AWS Account ID: `123456789012`
   - Enter ECR Repository Name: `clinicmanagementsystem`
   - Enter image tag: `latest` (or version number)

3. **Script will automatically**:
   - Authenticate with ECR
   - Create repository if it doesn't exist
   - Build the Docker image
   - Push to ECR

### Option 2: Using Docker Hub

1. **Run the build-push script**:
   ```bash
   ./scripts/build-push.sh
   ```

2. **Follow the prompts**:
   - Select registry type: `2` (Docker Hub)
   - Enter Docker Hub Username: `yourusername`
   - Enter Docker Hub Password: `yourpassword`
   - Enter image tag: `latest`

### Manual Build and Push

**For AWS ECR**:
```bash
# Authenticate
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com

# Build
docker build -t clinicmanagementsystem:latest .

# Tag
docker tag clinicmanagementsystem:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/clinicmanagementsystem:latest

# Push
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/clinicmanagementsystem:latest
```

---

## Deploying to AWS ECS

### Automated Deployment

1. **Run the deployment script**:
   
   **Linux/macOS**:
   ```bash
   chmod +x scripts/deploy-image.sh
   ./scripts/deploy-image.sh
   ```
   
   **Windows**:
   ```cmd
   scripts\deploy-image.bat
   ```

2. **Provide the required information**:
   - AWS Region: `us-east-1`
   - ECS Cluster Name: `clinic-cluster`
   - VPC ID: `vpc-xxxxx`
   - Subnet IDs: `subnet-xxxxx,subnet-yyyyy`
   - Security Group ID: `sg-xxxxx`
   - Docker Image URI: `123456789012.dkr.ecr.us-east-1.amazonaws.com/clinicmanagementsystem:latest`
   - Database Connection String: `Data Source=xxx;Initial Catalog=DBProject;User ID=xxx;Password=xxx`
   - Redis Connection String: `xxx.cache.amazonaws.com:6379` (optional)
   - Load Balancer: `y` or `n`

3. **Script will automatically**:
   - Create or update ECS cluster
   - Create Application Load Balancer and Target Group (if requested)
   - Register task definition
   - Create or update ECS service
   - Wait for service to stabilize
   - Display deployment summary

### Manual Deployment

1. **Register Task Definition**:
   ```bash
   aws ecs register-task-definition --cli-input-json file://ecs/task-definition.json --region us-east-1
   ```

2. **Create ECS Service**:
   ```bash
   aws ecs create-service --cli-input-json file://ecs/service-definition.json --region us-east-1
   ```

3. **Update Existing Service**:
   ```bash
   aws ecs update-service --cluster clinic-cluster --service clinicmanagementsystem-service --task-definition clinicmanagementsystem-task:1 --force-new-deployment --region us-east-1
   ```

---

## Configuration Management

### Environment Variables

The application uses the following environment variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `ASPNET_ENVIRONMENT` | Application environment | `Production` |
| `DB_CONNECTION_STRING` | SQL Server connection string | `Data Source=xxx;Initial Catalog=DBProject;User ID=xxx;Password=xxx` |
| `REDIS_CONNECTION_STRING` | Redis connection string (optional) | `xxx.cache.amazonaws.com:6379` |

### Updating Configuration

1. **Update task definition** (`ecs/task-definition.json`):
   ```json
   "environment": [
     {
       "name": "ASPNET_ENVIRONMENT",
       "value": "Production"
     },
     {
       "name": "DB_CONNECTION_STRING",
       "value": "your-connection-string"
     }
   ]
   ```

2. **Register new task definition**:
   ```bash
   aws ecs register-task-definition --cli-input-json file://ecs/task-definition.json
   ```

3. **Update service**:
   ```bash
   aws ecs update-service --cluster clinic-cluster --service clinicmanagementsystem-service --task-definition clinicmanagementsystem-task:2
   ```

### Using AWS Secrets Manager (Recommended)

1. **Store secrets**:
   ```bash
   aws secretsmanager create-secret --name clinic/db-connection --secret-string "your-connection-string"
   ```

2. **Update task definition** to use secrets:
   ```json
   "secrets": [
     {
       "name": "DB_CONNECTION_STRING",
       "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:clinic/db-connection"
     }
   ]
   ```

---

## Monitoring and Logging

### CloudWatch Logs

1. **View logs in real-time**:
   ```bash
   aws logs tail /ecs/clinicmanagementsystem --follow --region us-east-1
   ```

2. **View logs for specific time range**:
   ```bash
   aws logs filter-log-events --log-group-name /ecs/clinicmanagementsystem --start-time 1609459200000 --end-time 1609545600000
   ```

3. **Access logs via AWS Console**:
   - Navigate to CloudWatch > Log groups
   - Select `/ecs/clinicmanagementsystem`
   - View log streams

### CloudWatch Metrics

Monitor the following metrics:
- **CPUUtilization**: Task CPU usage
- **MemoryUtilization**: Task memory usage
- **TargetResponseTime**: Application response time
- **HealthyHostCount**: Number of healthy tasks
- **UnHealthyHostCount**: Number of unhealthy tasks

### Application Insights

The application includes Application Insights for detailed monitoring:
- Request tracking
- Dependency tracking
- Exception tracking
- Performance counters

### Health Checks

1. **Container Health Check**:
   - Endpoint: `/Helpers/HealthCheckHandler.ashx`
   - Interval: 30 seconds
   - Timeout: 5 seconds
   - Retries: 3
   - Start period: 60 seconds

2. **Load Balancer Health Check**:
   - Protocol: HTTP
   - Path: `/Helpers/HealthCheckHandler.ashx`
   - Interval: 30 seconds
   - Timeout: 5 seconds
   - Healthy threshold: 2
   - Unhealthy threshold: 3

---

## Troubleshooting

### Common Issues

#### 1. Task Fails to Start

**Symptoms**: Tasks are stuck in PENDING or immediately fail

**Possible Causes**:
- Insufficient CPU/memory allocation
- Image pull errors
- Network configuration issues
- IAM permission issues

**Solutions**:
```bash
# Check task stopped reason
aws ecs describe-tasks --cluster clinic-cluster --tasks task-id --region us-east-1

# Check CloudWatch logs
aws logs tail /ecs/clinicmanagementsystem --follow

# Verify IAM roles
aws iam get-role --role-name ecsTaskExecutionRole

# Check security group rules
aws ec2 describe-security-groups --group-ids sg-xxxxx
```

#### 2. Health Check Failures

**Symptoms**: Tasks are marked as unhealthy and replaced

**Possible Causes**:
- Application not responding on port 80
- Health check endpoint not accessible
- Slow application startup
- Database connection issues

**Solutions**:
```bash
# Increase health check grace period
aws ecs update-service --cluster clinic-cluster --service clinicmanagementsystem-service --health-check-grace-period-seconds 300

# Check application logs
aws logs tail /ecs/clinicmanagementsystem --follow

# Test health endpoint locally
docker run -p 8080:80 clinicmanagementsystem:latest
curl http://localhost:8080/Helpers/HealthCheckHandler.ashx
```

#### 3. Database Connection Errors

**Symptoms**: Application logs show database connection failures

**Possible Causes**:
- Incorrect connection string
- Database not accessible from ECS tasks
- Security group rules blocking traffic
- Database credentials incorrect

**Solutions**:
```bash
# Verify connection string in task definition
aws ecs describe-task-definition --task-definition clinicmanagementsystem-task

# Check security group rules for database
aws ec2 describe-security-groups --group-ids sg-database

# Test database connectivity from task
aws ecs execute-command --cluster clinic-cluster --task task-id --container clinicmanagementsystem --interactive --command "powershell"
```

#### 4. Out of Memory Errors

**Symptoms**: Tasks are killed due to memory exhaustion

**Solutions**:
```bash
# Increase memory allocation in task definition
# Edit ecs/task-definition.json
"memory": "2048"  # Increase from 1024

# Register new task definition
aws ecs register-task-definition --cli-input-json file://ecs/task-definition.json

# Update service
aws ecs update-service --cluster clinic-cluster --service clinicmanagementsystem-service --task-definition clinicmanagementsystem-task:new-version
```

#### 5. Load Balancer 502/503 Errors

**Symptoms**: Load balancer returns 502 Bad Gateway or 503 Service Unavailable

**Possible Causes**:
- No healthy targets
- Health check failures
- Application not responding
- Target group misconfiguration

**Solutions**:
```bash
# Check target health
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:...

# Check service events
aws ecs describe-services --cluster clinic-cluster --services clinicmanagementsystem-service

# Verify target group settings
aws elbv2 describe-target-groups --target-group-arns arn:aws:elasticloadbalancing:...
```

### Debugging Commands

```bash
# List all tasks in cluster
aws ecs list-tasks --cluster clinic-cluster --region us-east-1

# Describe specific task
aws ecs describe-tasks --cluster clinic-cluster --tasks task-id --region us-east-1

# View service events
aws ecs describe-services --cluster clinic-cluster --services clinicmanagementsystem-service --region us-east-1

# Check task definition
aws ecs describe-task-definition --task-definition clinicmanagementsystem-task --region us-east-1

# View CloudWatch logs
aws logs tail /ecs/clinicmanagementsystem --follow --region us-east-1

# Execute command in running task
aws ecs execute-command --cluster clinic-cluster --task task-id --container clinicmanagementsystem --interactive --command "powershell"
```

---

## Security Considerations

### Network Security

1. **Use Private Subnets** (recommended for production):
   - Place ECS tasks in private subnets
   - Use NAT Gateway for outbound connectivity
   - Only expose load balancer in public subnets

2. **Security Group Rules**:
   - Restrict inbound traffic to necessary ports only
   - Use security group references instead of CIDR blocks
   - Implement least privilege access

3. **VPC Flow Logs**:
   ```bash
   aws ec2 create-flow-logs --resource-type VPC --resource-ids vpc-xxxxx --traffic-type ALL --log-destination-type cloud-watch-logs --log-group-name /aws/vpc/flowlogs
   ```

### Application Security

1. **Use HTTPS**:
   - Configure SSL/TLS certificate on load balancer
   - Redirect HTTP to HTTPS
   - Use AWS Certificate Manager (ACM)

2. **Secrets Management**:
   - Store sensitive data in AWS Secrets Manager
   - Use IAM roles for authentication
   - Rotate secrets regularly

3. **Database Security**:
   - Use encrypted connections (SSL/TLS)
   - Implement least privilege database access
   - Enable encryption at rest

4. **Container Security**:
   - Use official Microsoft base images
   - Scan images for vulnerabilities
   - Keep base images updated
   - Run containers as non-root (when possible)

### IAM Security

1. **Task Execution Role**:
   - Minimum permissions: ECR pull, CloudWatch Logs write
   - Use managed policies when possible
   - Implement resource-based policies

2. **Task Role**:
   - Grant only necessary AWS service permissions
   - Use condition keys for fine-grained access
   - Implement least privilege principle

### Compliance

1. **Enable AWS Config**:
   - Monitor ECS configuration changes
   - Ensure compliance with security standards

2. **Enable CloudTrail**:
   - Audit all API calls
   - Monitor for suspicious activity

3. **Implement Backup Strategy**:
   - Regular database backups
   - Configuration backups
   - Disaster recovery plan

---

## Scaling and Performance

### Auto Scaling

1. **Configure Service Auto Scaling**:
   ```bash
   # Register scalable target
   aws application-autoscaling register-scalable-target \
     --service-namespace ecs \
     --scalable-dimension ecs:service:DesiredCount \
     --resource-id service/clinic-cluster/clinicmanagementsystem-service \
     --min-capacity 2 \
     --max-capacity 10
   
   # Create scaling policy (CPU-based)
   aws application-autoscaling put-scaling-policy \
     --service-namespace ecs \
     --scalable-dimension ecs:service:DesiredCount \
     --resource-id service/clinic-cluster/clinicmanagementsystem-service \
     --policy-name cpu-scaling-policy \
     --policy-type TargetTrackingScaling \
     --target-tracking-scaling-policy-configuration file://scaling-policy.json
   ```

   **scaling-policy.json**:
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

2. **Memory-based Scaling**:
   ```json
   {
     "TargetValue": 80.0,
     "PredefinedMetricSpecification": {
       "PredefinedMetricType": "ECSServiceAverageMemoryUtilization"
     }
   }
   ```

3. **Request Count Scaling**:
   ```json
   {
     "TargetValue": 1000.0,
     "PredefinedMetricSpecification": {
       "PredefinedMetricType": "ALBRequestCountPerTarget",
       "ResourceLabel": "app/clinic-alb/xxx/targetgroup/clinic-tg/yyy"
     }
   }
   ```

### Performance Optimization

1. **Task CPU and Memory**:
   - Monitor actual usage
   - Adjust task definition accordingly
   - Use appropriate Fargate CPU/memory combinations

2. **Connection Pooling**:
   - Configure database connection pooling
   - Optimize connection string parameters
   - Monitor connection usage

3. **Caching**:
   - Implement Redis for session state
   - Cache frequently accessed data
   - Use CDN for static assets

4. **Application Insights**:
   - Monitor slow requests
   - Identify performance bottlenecks
   - Optimize database queries

### Blue/Green Deployment

1. **Using AWS CodeDeploy**:
   ```bash
   # Create deployment group
   aws deploy create-deployment-group \
     --application-name clinic-app \
     --deployment-group-name clinic-deployment-group \
     --deployment-config-name CodeDeployDefault.ECSAllAtOnce \
     --service-role-arn arn:aws:iam::123456789012:role/CodeDeployServiceRole \
     --ecs-services clusterName=clinic-cluster,serviceName=clinicmanagementsystem-service \
     --load-balancer-info targetGroupInfoList=[{name=clinic-tg}]
   
   # Create deployment
   aws deploy create-deployment \
     --application-name clinic-app \
     --deployment-group-name clinic-deployment-group \
     --revision revisionType=AppSpecContent,appSpecContent={content=file://appspec.yaml}
   ```

2. **Manual Blue/Green**:
   - Create new task definition version
   - Update service with new task definition
   - Monitor deployment progress
   - Rollback if issues detected

---

## Cost Optimization

### Fargate Pricing Considerations

1. **Right-size Tasks**:
   - Monitor actual CPU/memory usage
   - Use smallest viable configuration
   - Adjust based on metrics

2. **Spot Capacity** (if applicable):
   - Use Fargate Spot for non-critical workloads
   - Implement graceful shutdown handling

3. **Reserved Capacity** (Savings Plans):
   - Commit to consistent usage
   - Save up to 50% on compute costs

### Monitoring Costs

```bash
# View ECS costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --filter file://cost-filter.json
```

---

## Additional Resources

### AWS Documentation
- [Amazon ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [AWS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [Amazon ECR Documentation](https://docs.aws.amazon.com/ecr/)
- [CloudWatch Logs Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/)

### Microsoft Documentation
- [ASP.NET Framework Documentation](https://docs.microsoft.com/en-us/aspnet/overview)
- [Windows Container Documentation](https://docs.microsoft.com/en-us/virtualization/windowscontainers/)
- [IIS Documentation](https://docs.microsoft.com/en-us/iis/)

### Support
For issues or questions:
1. Check CloudWatch logs for error messages
2. Review ECS service events
3. Consult AWS Support (if applicable)
4. Review application-specific documentation

---

## Appendix

### Valid Fargate CPU/Memory Combinations

| CPU (vCPU) | Memory (MB) |
|------------|-------------|
| 0.25 (256) | 512, 1024, 2048 |
| 0.5 (512)  | 1024, 2048, 3072, 4096 |
| 1 (1024)   | 2048, 3072, 4096, 5120, 6144, 7168, 8192 |
| 2 (2048)   | 4096 to 16384 (increments of 1024) |
| 4 (4096)   | 8192 to 30720 (increments of 1024) |

### Useful AWS CLI Commands

```bash
# List ECS clusters
aws ecs list-clusters --region us-east-1

# List services in cluster
aws ecs list-services --cluster clinic-cluster --region us-east-1

# List tasks in service
aws ecs list-tasks --cluster clinic-cluster --service-name clinicmanagementsystem-service --region us-east-1

# Describe task
aws ecs describe-tasks --cluster clinic-cluster --tasks task-id --region us-east-1

# Update service desired count
aws ecs update-service --cluster clinic-cluster --service clinicmanagementsystem-service --desired-count 3 --region us-east-1

# Force new deployment
aws ecs update-service --cluster clinic-cluster --service clinicmanagementsystem-service --force-new-deployment --region us-east-1

# Delete service
aws ecs delete-service --cluster clinic-cluster --service clinicmanagementsystem-service --force --region us-east-1

# Delete cluster
aws ecs delete-cluster --cluster clinic-cluster --region us-east-1
```

---

**Document Version**: 1.0  
**Last Updated**: 2024  
**Maintained By**: DevOps Team
