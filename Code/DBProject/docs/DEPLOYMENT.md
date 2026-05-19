# DBProject - AWS ECS Fargate Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Project Architecture](#project-architecture)
4. [Local Development Setup](#local-development-setup)
5. [Docker Containerization](#docker-containerization)
6. [AWS ECS Fargate Deployment](#aws-ecs-fargate-deployment)
7. [Configuration Management](#configuration-management)
8. [Monitoring and Logging](#monitoring-and-logging)
9. [Troubleshooting](#troubleshooting)
10. [Security Considerations](#security-considerations)

---

## Overview

DBProject is an ASP.NET Framework 4.5.2 web application designed for healthcare management. This guide provides comprehensive instructions for containerizing and deploying the application to AWS ECS Fargate.

**Technology Stack:**
- **Framework**: ASP.NET Framework 4.5.2
- **Runtime**: .NET Framework 4.8 (Windows Containers)
- **Web Server**: IIS (Internet Information Services)
- **Database**: SQL Server
- **Container Platform**: Docker (Windows Containers)
- **Deployment Target**: AWS ECS Fargate

---

## Prerequisites

### Required Software
1. **Docker Desktop for Windows**
   - Version: 4.x or later
   - Windows Containers mode enabled
   - Download: https://www.docker.com/products/docker-desktop

2. **AWS CLI**
   - Version: 2.x or later
   - Installation: https://aws.amazon.com/cli/
   ```bash
   aws --version
   ```

3. **AWS Account**
   - Active AWS account with appropriate permissions
   - IAM user with ECS, ECR, VPC, and CloudWatch permissions

4. **Git** (optional)
   - For version control
   - Download: https://git-scm.com/

### AWS IAM Permissions Required
Your AWS IAM user/role needs the following permissions:
- `AmazonECS_FullAccess`
- `AmazonEC2ContainerRegistryFullAccess`
- `CloudWatchLogsFullAccess`
- `IAMReadOnlyAccess`
- `AmazonVPCFullAccess` (for network configuration)
- `ElasticLoadBalancingFullAccess` (if using ALB)

### AWS Resources Required
1. **VPC** with at least 2 subnets in different availability zones
2. **Security Group** allowing inbound traffic on port 80
3. **RDS SQL Server instance** (or external SQL Server)
4. **ECR Repository** (will be created by build script if not exists)

---

## Project Architecture

### Application Structure
```
DBProject/
├── Admin/              # Admin portal pages
├── Doctor/             # Doctor portal pages
├── Patient/            # Patient portal pages
├── DAL/                # Data Access Layer
├── assets/             # Static assets (CSS, JS, images)
├── Web.config          # Application configuration
├── Dockerfile          # Docker build instructions
├── docker-compose.yml  # Local development orchestration
├── .dockerignore       # Docker build exclusions
├── scripts/            # Build and deployment scripts
│   ├── build-push.sh
│   ├── build-push.bat
│   ├── deploy-image.sh
│   └── deploy-image.bat
├── ecs/                # ECS deployment manifests
│   ├── task-definition.json
│   └── service-definition.json
└── docs/               # Documentation
    └── DEPLOYMENT.md
```

### Container Architecture
- **Base Image**: `mcr.microsoft.com/dotnet/framework/aspnet:4.8`
- **Build Image**: `mcr.microsoft.com/dotnet/framework/sdk:4.8`
- **Multi-stage Build**: Yes (builder + runtime)
- **Container Type**: Windows Container
- **Exposed Port**: 80 (HTTP)

---

## Local Development Setup

### 1. Clone the Repository
```bash
git clone <repository-url>
cd DBProject
```

### 2. Configure Database Connection
Edit `Web.config` and update the connection string:
```xml
<connectionStrings>
  <add name="sqlCon1" 
       connectionString="Data Source=YOUR_DB_HOST;Initial Catalog=DBProject;User ID=YOUR_USER;Password=YOUR_PASSWORD" 
       providerName="System.Data.SqlClient" />
</connectionStrings>
```

### 3. Build and Run Locally with Docker

**Using Docker Compose:**
```bash
# Build the image
docker-compose build

# Run the container
docker-compose up -d

# View logs
docker-compose logs -f

# Access the application
# Open browser: http://localhost:8080
```

**Using Docker CLI:**
```bash
# Build the image
docker build -t dbproject:latest .

# Run the container
docker run -d -p 8080:80 --name dbproject dbproject:latest

# View logs
docker logs -f dbproject

# Stop the container
docker stop dbproject
docker rm dbproject
```

### 4. Verify Local Deployment
- Open browser: `http://localhost:8080`
- You should see the DBProject home page
- Test login and basic functionality

---

## Docker Containerization

### Understanding the Dockerfile

The Dockerfile uses a multi-stage build approach:

**Stage 1: Builder**
```dockerfile
FROM mcr.microsoft.com/dotnet/framework/sdk:4.8 AS builder
# Restores NuGet packages
# Builds the application using MSBuild
# Publishes to C:\publish
```

**Stage 2: Runtime**
```dockerfile
FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8
# Copies published application
# Configures IIS settings
# Exposes port 80
```

### Build Optimization
The Dockerfile is optimized for:
- **Layer Caching**: Dependencies restored before source code copy
- **Size Reduction**: Multi-stage build discards build tools
- **Performance**: IIS configured for production workloads

### .dockerignore
Excludes unnecessary files from the build context:
- Build artifacts (`bin/`, `obj/`)
- IDE files (`.vs/`, `.vscode/`)
- Version control (`.git/`)
- Documentation (`*.md`)

---

## AWS ECS Fargate Deployment

### Architecture Overview

```
Internet
    ↓
Application Load Balancer (Optional)
    ↓
ECS Service (Fargate)
    ↓
ECS Tasks (2 replicas)
    ↓
Windows Containers (DBProject)
    ↓
RDS SQL Server
```

### Step 1: Build and Push Docker Image

**On Linux/macOS:**
```bash
cd /path/to/DBProject
chmod +x scripts/build-push.sh
./scripts/build-push.sh
```

**On Windows:**
```cmd
cd C:\path\to\DBProject
scripts\build-push.bat
```

**Interactive Prompts:**
1. Select registry type (1=ECR, 2=Docker Hub)
2. Enter registry credentials
3. Enter image tag (default: latest)

**Example Output:**
```
Building Docker Image
Image: 123456789.dkr.ecr.us-east-1.amazonaws.com/dbproject:latest

Pushing Docker Image
The push refers to repository [123456789.dkr.ecr.us-east-1.amazonaws.com/dbproject]
latest: digest: sha256:abc123... size: 4567

Build and Push Completed Successfully!
```

### Step 2: Configure AWS Resources

#### Create VPC and Subnets (if not exists)
```bash
# Create VPC
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region us-east-1

# Create Subnets
aws ec2 create-subnet --vpc-id vpc-xxx --cidr-block 10.0.1.0/24 --availability-zone us-east-1a
aws ec2 create-subnet --vpc-id vpc-xxx --cidr-block 10.0.2.0/24 --availability-zone us-east-1b
```

#### Create Security Group
```bash
# Create security group
aws ec2 create-security-group \
  --group-name dbproject-sg \
  --description "Security group for DBProject ECS tasks" \
  --vpc-id vpc-xxx

# Allow inbound HTTP traffic
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxx \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0
```

#### Create IAM Roles

**ECS Task Execution Role:**
```bash
# Create trust policy
cat > ecs-trust-policy.json <<EOF
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
EOF

# Create role
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://ecs-trust-policy.json

# Attach policy
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

**ECS Task Role (for application permissions):**
```bash
# Create role
aws iam create-role \
  --role-name ecsTaskRole \
  --assume-role-policy-document file://ecs-trust-policy.json

# Attach policies as needed (e.g., S3, RDS, etc.)
```

### Step 3: Deploy to ECS Fargate

**On Linux/macOS:**
```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

**On Windows:**
```cmd
scripts\deploy-image.bat
```

**Interactive Prompts:**
1. AWS region (e.g., us-east-1)
2. ECS cluster name (e.g., dbproject-cluster)
3. VPC ID (e.g., vpc-0abc123def456)
4. Subnet IDs (comma-separated)
5. Security Group ID (e.g., sg-0abc123def)
6. Docker image URI (from Step 1)
7. Database configuration (host, user, password)
8. Load balancer requirement (y/n)

**Deployment Process:**
1. ✅ Validates AWS credentials
2. ✅ Creates/verifies ECS cluster
3. ✅ Creates Application Load Balancer (if requested)
4. ✅ Creates Target Group with health checks
5. ✅ Creates CloudWatch Log Group
6. ✅ Registers ECS Task Definition
7. ✅ Creates/Updates ECS Service
8. ✅ Waits for service stability
9. ✅ Displays deployment status

**Example Output:**
```
==========================================
Deployment Completed Successfully!
==========================================

Service Details:
-------------------------------------------------
|           DescribeServices                    |
+---------------+--------+----------+-----------+
| dbproject-service | ACTIVE | 2        | 2         |
+---------------+--------+----------+-----------+

Application URL: http://dbproject-alb-123456789.us-east-1.elb.amazonaws.com

CloudWatch Logs: /ecs/dbproject
Region: us-east-1
```

### Step 4: Verify Deployment

**Check Service Status:**
```bash
aws ecs describe-services \
  --cluster dbproject-cluster \
  --services dbproject-service \
  --region us-east-1
```

**Check Running Tasks:**
```bash
aws ecs list-tasks \
  --cluster dbproject-cluster \
  --service-name dbproject-service \
  --region us-east-1
```

**View Logs:**
```bash
aws logs tail /ecs/dbproject --follow --region us-east-1
```

**Access Application:**
- If using ALB: `http://<alb-dns-name>`
- If using public IP: Get task public IP from ECS console

---

## Configuration Management

### Environment Variables

The application uses environment variables for configuration:

| Variable | Description | Example |
|----------|-------------|---------|
| `ASPNET_ENVIRONMENT` | Application environment | `Production` |
| `ConnectionStrings__sqlCon1` | Database connection string | `Data Source=...` |

### Task Definition Configuration

**CPU and Memory:**
- Default: 512 CPU units (0.5 vCPU), 1024 MB memory
- Valid Fargate combinations:
  - CPU: 256 → Memory: 512, 1024, 2048 MB
  - CPU: 512 → Memory: 1024, 2048, 3072, 4096 MB
  - CPU: 1024 → Memory: 2048-8192 MB

**Modify in `ecs/task-definition.json`:**
```json
{
  "cpu": "512",
  "memory": "1024"
}
```

### Service Scaling

**Update Desired Count:**
```bash
aws ecs update-service \
  --cluster dbproject-cluster \
  --service dbproject-service \
  --desired-count 4 \
  --region us-east-1
```

**Enable Auto Scaling:**
```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/dbproject-cluster/dbproject-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10

# Create scaling policy
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/dbproject-cluster/dbproject-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name cpu-scaling-policy \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration file://scaling-policy.json
```

---

## Monitoring and Logging

### CloudWatch Logs

**Log Group:** `/ecs/dbproject`

**View Logs:**
```bash
# Tail logs in real-time
aws logs tail /ecs/dbproject --follow --region us-east-1

# Filter logs
aws logs filter-log-events \
  --log-group-name /ecs/dbproject \
  --filter-pattern "ERROR" \
  --region us-east-1
```

### CloudWatch Metrics

**Key Metrics to Monitor:**
- `CPUUtilization`: Task CPU usage
- `MemoryUtilization`: Task memory usage
- `TargetResponseTime`: ALB response time
- `HealthyHostCount`: Number of healthy targets
- `UnHealthyHostCount`: Number of unhealthy targets

**Create CloudWatch Dashboard:**
```bash
aws cloudwatch put-dashboard \
  --dashboard-name DBProject-Dashboard \
  --dashboard-body file://dashboard.json
```

### Application Insights

The application includes Application Insights for telemetry:
- Request tracking
- Dependency tracking
- Exception logging
- Performance counters

**Configure in `ApplicationInsights.config`**

---

## Troubleshooting

### Common Issues and Solutions

#### 1. Task Fails to Start

**Symptoms:**
- Tasks transition from PENDING to STOPPED
- Error: "CannotPullContainerError"

**Solutions:**
```bash
# Check task stopped reason
aws ecs describe-tasks \
  --cluster dbproject-cluster \
  --tasks <task-id> \
  --region us-east-1

# Verify ECR permissions
aws ecr get-login-password --region us-east-1

# Check execution role has ECR permissions
aws iam get-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-name AmazonECSTaskExecutionRolePolicy
```

#### 2. Health Check Failures

**Symptoms:**
- Tasks marked as unhealthy
- Service keeps replacing tasks

**Solutions:**
```bash
# Check task logs
aws logs tail /ecs/dbproject --follow

# Verify application is listening on port 80
# Increase health check grace period in service definition
"healthCheckGracePeriodSeconds": 300

# Adjust health check parameters in target group
aws elbv2 modify-target-group \
  --target-group-arn <arn> \
  --health-check-interval-seconds 60 \
  --health-check-timeout-seconds 10 \
  --healthy-threshold-count 2
```

#### 3. Database Connection Errors

**Symptoms:**
- Application logs show SQL connection errors
- Tasks fail to start or crash

**Solutions:**
```bash
# Verify security group allows outbound to RDS
aws ec2 describe-security-groups --group-ids sg-xxx

# Check RDS security group allows inbound from ECS tasks
# Verify connection string in task definition
# Test connectivity from ECS task:
aws ecs execute-command \
  --cluster dbproject-cluster \
  --task <task-id> \
  --container dbproject \
  --interactive \
  --command "powershell"
```

#### 4. Out of Memory Errors

**Symptoms:**
- Tasks stop with exit code 137
- Logs show OutOfMemoryException

**Solutions:**
```bash
# Increase memory allocation in task definition
# Edit ecs/task-definition.json:
"memory": "2048"

# Re-register task definition and update service
aws ecs register-task-definition --cli-input-json file://ecs/task-definition.json
aws ecs update-service --cluster dbproject-cluster --service dbproject-service --task-definition dbproject-task
```

#### 5. Windows Container Issues

**Symptoms:**
- Container fails to start on Fargate
- Error: "Windows containers not supported"

**Solutions:**
- **Note**: AWS Fargate currently supports only Linux containers
- For Windows containers, use **ECS on EC2** with Windows Server instances
- Alternative: Migrate application to .NET Core/ASP.NET Core for Linux container support

**Migration Path:**
1. Assess application for .NET Core compatibility
2. Update to .NET Framework 4.8 (if not already)
3. Consider migrating to ASP.NET Core for full Linux support
4. Use AWS App2Container for automated migration

---

## Security Considerations

### 1. Network Security

**VPC Configuration:**
- Use private subnets for ECS tasks
- Use NAT Gateway for outbound internet access
- Restrict security group rules to minimum required

**Security Group Rules:**
```bash
# Allow inbound only from ALB
aws ec2 authorize-security-group-ingress \
  --group-id sg-ecs-tasks \
  --protocol tcp \
  --port 80 \
  --source-group sg-alb

# Allow outbound to RDS
aws ec2 authorize-security-group-egress \
  --group-id sg-ecs-tasks \
  --protocol tcp \
  --port 1433 \
  --destination-group sg-rds
```

### 2. Secrets Management

**Use AWS Secrets Manager:**
```bash
# Store database password
aws secretsmanager create-secret \
  --name dbproject/db-password \
  --secret-string "YourSecurePassword"

# Reference in task definition
{
  "secrets": [
    {
      "name": "DB_PASSWORD",
      "valueFrom": "arn:aws:secretsmanager:region:account:secret:dbproject/db-password"
    }
  ]
}
```

### 3. IAM Best Practices

- Use least privilege principle
- Separate execution role and task role
- Enable CloudTrail for audit logging
- Rotate credentials regularly

### 4. Container Security

- Use official Microsoft base images
- Scan images for vulnerabilities
- Keep base images updated
- Implement runtime security monitoring

**Scan Image:**
```bash
# Using AWS ECR image scanning
aws ecr start-image-scan \
  --repository-name dbproject \
  --image-id imageTag=latest

# View scan results
aws ecr describe-image-scan-findings \
  --repository-name dbproject \
  --image-id imageTag=latest
```

### 5. Data Encryption

- Enable encryption at rest for RDS
- Use SSL/TLS for database connections
- Enable ALB HTTPS listener with ACM certificate
- Encrypt CloudWatch Logs

---

## Additional Resources

### AWS Documentation
- [ECS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [ECS Task Definitions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)
- [ECR User Guide](https://docs.aws.amazon.com/AmazonECR/latest/userguide/)

### Microsoft Documentation
- [ASP.NET Framework Documentation](https://docs.microsoft.com/en-us/aspnet/overview)
- [Windows Container Documentation](https://docs.microsoft.com/en-us/virtualization/windowscontainers/)
- [.NET Framework Docker Images](https://hub.docker.com/_/microsoft-dotnet-framework)

### Support
For issues or questions:
1. Check CloudWatch Logs: `/ecs/dbproject`
2. Review ECS service events
3. Consult AWS Support
4. Review application logs

---

## Appendix

### A. Valid Fargate CPU/Memory Combinations

| CPU (vCPU) | Memory (MB) |
|------------|-------------|
| 0.25 (256) | 512, 1024, 2048 |
| 0.5 (512)  | 1024, 2048, 3072, 4096 |
| 1 (1024)   | 2048, 3072, 4096, 5120, 6144, 7168, 8192 |
| 2 (2048)   | 4096 to 16384 (increments of 1024) |
| 4 (4096)   | 8192 to 30720 (increments of 1024) |

### B. AWS CLI Configuration

```bash
# Configure AWS CLI
aws configure

# Set default region
aws configure set region us-east-1

# Verify configuration
aws sts get-caller-identity
```

### C. Useful Commands

```bash
# List ECS clusters
aws ecs list-clusters

# List services in cluster
aws ecs list-services --cluster dbproject-cluster

# List tasks in service
aws ecs list-tasks --cluster dbproject-cluster --service-name dbproject-service

# Describe task
aws ecs describe-tasks --cluster dbproject-cluster --tasks <task-id>

# Stop task (force new deployment)
aws ecs stop-task --cluster dbproject-cluster --task <task-id>

# Delete service
aws ecs delete-service --cluster dbproject-cluster --service dbproject-service --force

# Delete cluster
aws ecs delete-cluster --cluster dbproject-cluster
```

---

**Document Version:** 1.0  
**Last Updated:** 2024  
**Maintained By:** DevOps Team
