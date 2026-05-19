#!/bin/bash

# AWS ECS Fargate Deployment Script for DBProject
# This script deploys the containerized application to AWS ECS Fargate

set -e
set -o pipefail

echo "=========================================="
echo "AWS ECS Fargate Deployment Script"
echo "=========================================="
echo ""

# Prompt for AWS configuration
read -p "Enter AWS region (e.g., us-east-1): " AWS_REGION
read -p "Enter ECS cluster name (e.g., dbproject-cluster): " CLUSTER_NAME
read -p "Enter VPC ID (e.g., vpc-0abc123def456): " VPC_ID
read -p "Enter Subnet IDs comma-separated (e.g., subnet-0abc123,subnet-0def456): " SUBNETS_INPUT
read -p "Enter Security Group ID (e.g., sg-0abc123def): " SECURITY_GROUP
read -p "Enter Docker image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/dbproject:latest): " IMAGE_URI

# Parse subnets
IFS=',' read -ra SUBNETS <<< "$SUBNETS_INPUT"
SUBNET_1="${SUBNETS[0]}"
SUBNET_2="${SUBNETS[1]:-$SUBNET_1}"

# Get AWS Account ID
echo ""
echo "Retrieving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"

# Database configuration
echo ""
echo "=== Database Configuration ==="
read -p "Enter Database Host (e.g., mydb.abc123.us-east-1.rds.amazonaws.com): " DB_HOST
read -p "Enter Database User: " DB_USER
read -sp "Enter Database Password: " DB_PASSWORD
echo ""

# Check if ECS cluster exists, create if not
echo ""
echo "Checking ECS cluster..."
if ! aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" 2>/dev/null | grep -q "ACTIVE"; then
    echo "Creating ECS cluster: $CLUSTER_NAME"
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"
else
    echo "ECS cluster already exists: $CLUSTER_NAME"
fi

# Ask about load balancer
echo ""
read -p "Do you need a load balancer for this service? (y/n): " NEED_LB

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
    echo ""
    echo "=== Creating Application Load Balancer ==="
    
    # Create ALB
    ALB_NAME="dbproject-alb"
    echo "Creating Application Load Balancer: $ALB_NAME"
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "$ALB_NAME" \
        --subnets "$SUBNET_1" "$SUBNET_2" \
        --security-groups "$SECURITY_GROUP" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$ALB_ARN" ]; then
        echo "Load balancer may already exist, retrieving ARN..."
        ALB_ARN=$(aws elbv2 describe-load-balancers \
            --names "$ALB_NAME" \
            --region "$AWS_REGION" \
            --query 'LoadBalancers[0].LoadBalancerArn' \
            --output text)
    fi
    
    echo "Load Balancer ARN: $ALB_ARN"
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    # Create Target Group
    TG_NAME="dbproject-tg"
    echo "Creating Target Group: $TG_NAME"
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "$TG_NAME" \
        --protocol HTTP \
        --port 80 \
        --vpc-id "$VPC_ID" \
        --target-type ip \
        --health-check-enabled \
        --health-check-protocol HTTP \
        --health-check-path "/" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$TARGET_GROUP_ARN" ]; then
        echo "Target group may already exist, retrieving ARN..."
        TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
            --names "$TG_NAME" \
            --region "$AWS_REGION" \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text)
    fi
    
    echo "Target Group ARN: $TARGET_GROUP_ARN"
    
    # Create Listener
    echo "Creating ALB Listener..."
    aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
        --region "$AWS_REGION" 2>/dev/null || echo "Listener may already exist"
    
    # Update service definition with load balancer
    sed -i.bak "s|{{TARGET_GROUP_ARN}}|$TARGET_GROUP_ARN|g" ecs/service-definition.json
else
    echo "Skipping load balancer creation"
    # Remove loadBalancers section from service definition
    python3 -c "
import json
with open('ecs/service-definition.json', 'r') as f:
    data = json.load(f)
if 'loadBalancers' in data:
    del data['loadBalancers']
if 'healthCheckGracePeriodSeconds' in data:
    del data['healthCheckGracePeriodSeconds']
with open('ecs/service-definition.json', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || {
        # Fallback if python3 is not available
        echo "Warning: Could not remove loadBalancers section. Please edit ecs/service-definition.json manually."
    }
fi

# Create CloudWatch Log Group
echo ""
echo "Creating CloudWatch Log Group..."
aws logs create-log-group --log-group-name "/ecs/dbproject" --region "$AWS_REGION" 2>/dev/null || echo "Log group already exists"

# Replace placeholders in task definition
echo ""
echo "Preparing task definition..."
sed -i.bak "s|{{IMAGE_URI}}|$IMAGE_URI|g" ecs/task-definition.json
sed -i.bak "s|{{AWS_REGION}}|$AWS_REGION|g" ecs/task-definition.json
sed -i.bak "s|{{ACCOUNT_ID}}|$ACCOUNT_ID|g" ecs/task-definition.json
sed -i.bak "s|{{DB_HOST}}|$DB_HOST|g" ecs/task-definition.json
sed -i.bak "s|{{DB_USER}}|$DB_USER|g" ecs/task-definition.json
sed -i.bak "s|{{DB_PASSWORD}}|$DB_PASSWORD|g" ecs/task-definition.json

# Register task definition
echo "Registering ECS task definition..."
TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file://ecs/task-definition.json \
    --region "$AWS_REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo "Task Definition ARN: $TASK_DEF_ARN"

# Replace placeholders in service definition
echo ""
echo "Preparing service definition..."
sed -i.bak "s|{{CLUSTER_NAME}}|$CLUSTER_NAME|g" ecs/service-definition.json
sed -i.bak "s|{{SUBNET_1}}|$SUBNET_1|g" ecs/service-definition.json
sed -i.bak "s|{{SUBNET_2}}|$SUBNET_2|g" ecs/service-definition.json
sed -i.bak "s|{{SECURITY_GROUP}}|$SECURITY_GROUP|g" ecs/service-definition.json

# Check if service exists
echo "Checking if ECS service exists..."
SERVICE_EXISTS=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "dbproject-service" \
    --region "$AWS_REGION" \
    --query 'services[0].serviceName' \
    --output text 2>/dev/null || echo "None")

if [ "$SERVICE_EXISTS" == "None" ] || [ "$SERVICE_EXISTS" == "" ]; then
    echo "Creating new ECS service..."
    aws ecs create-service \
        --cli-input-json file://ecs/service-definition.json \
        --region "$AWS_REGION"
else
    echo "Updating existing ECS service..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "dbproject-service" \
        --task-definition "$TASK_DEF_ARN" \
        --desired-count 2 \
        --force-new-deployment \
        --region "$AWS_REGION"
fi

# Wait for service to stabilize
echo ""
echo "Waiting for service to become stable (this may take a few minutes)..."
aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services "dbproject-service" \
    --region "$AWS_REGION"

# Display deployment status
echo ""
echo "=========================================="
echo "Deployment Completed Successfully!"
echo "=========================================="
echo ""
echo "Service Details:"
aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "dbproject-service" \
    --region "$AWS_REGION" \
    --query 'services[0].[serviceName,status,runningCount,desiredCount]' \
    --output table

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Application URL: http://$ALB_DNS"
    echo ""
    echo "Note: It may take a few minutes for the load balancer to become healthy."
fi

echo ""
echo "CloudWatch Logs: /ecs/dbproject"
echo "Region: $AWS_REGION"
echo ""
echo "To view logs:"
echo "aws logs tail /ecs/dbproject --follow --region $AWS_REGION"
echo ""
