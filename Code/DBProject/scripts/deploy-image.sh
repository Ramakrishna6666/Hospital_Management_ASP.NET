#!/bin/bash
set -e
set -o pipefail

# Deploy Docker Image to AWS ECS Fargate
# Clinic Management System Deployment Script

echo "=========================================="
echo "AWS ECS Fargate Deployment Script"
echo "Clinic Management System"
echo "=========================================="
echo ""

# Prompt for AWS configuration
echo "=== AWS Configuration ==="
read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
read -p "Enter ECS Cluster Name (e.g., clinic-cluster): " CLUSTER_NAME
echo ""

# Get AWS Account ID
echo "Retrieving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to retrieve AWS Account ID. Please check AWS CLI configuration."
    exit 1
fi
echo "AWS Account ID: $ACCOUNT_ID"
echo ""

# Prompt for network configuration
echo "=== Network Configuration ==="
read -p "Enter VPC ID (e.g., vpc-0abc123def456): " VPC_ID
read -p "Enter Subnet IDs comma-separated (e.g., subnet-0abc123,subnet-0def456): " SUBNETS_INPUT
read -p "Enter Security Group ID (e.g., sg-0abc123def): " SECURITY_GROUP
echo ""

# Convert comma-separated subnets to array
IFS=',' read -ra SUBNETS <<< "$SUBNETS_INPUT"
SUBNET_1="${SUBNETS[0]}"
SUBNET_2="${SUBNETS[1]:-$SUBNET_1}"

# Prompt for Docker image URI
echo "=== Docker Image Configuration ==="
read -p "Enter Docker Image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/clinicmanagementsystem:latest): " IMAGE_URI
echo ""

# Prompt for database configuration
echo "=== Database Configuration ==="
read -p "Enter Database Connection String: " DB_CONNECTION_STRING
read -p "Enter Redis Connection String (optional, press Enter to skip): " REDIS_CONNECTION_STRING
REDIS_CONNECTION_STRING=${REDIS_CONNECTION_STRING:-""}
echo ""

# Check if ECS cluster exists, create if not
echo "Checking if ECS cluster exists..."
aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || {
    echo "Cluster does not exist. Creating ECS cluster..."
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"
    echo "ECS cluster created successfully"
}
echo ""

# Prompt for load balancer configuration
echo "=== Load Balancer Configuration ==="
read -p "Do you need a load balancer for this service? (y/n): " NEED_LB
echo ""

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
    echo "Creating Application Load Balancer and Target Group..."
    
    # Create Application Load Balancer
    ALB_NAME="clinic-alb-$(date +%s)"
    echo "Creating ALB: $ALB_NAME"
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "$ALB_NAME" \
        --subnets "$SUBNET_1" "$SUBNET_2" \
        --security-groups "$SECURITY_GROUP" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create Application Load Balancer"
        exit 1
    fi
    
    echo "ALB created: $ALB_ARN"
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    # Create Target Group with target-type ip (required for Fargate)
    TG_NAME="clinic-tg-$(date +%s)"
    echo "Creating Target Group: $TG_NAME"
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "$TG_NAME" \
        --protocol HTTP \
        --port 80 \
        --vpc-id "$VPC_ID" \
        --target-type ip \
        --health-check-enabled \
        --health-check-protocol HTTP \
        --health-check-path "/Helpers/HealthCheckHandler.ashx" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create Target Group"
        exit 1
    fi
    
    echo "Target Group created: $TARGET_GROUP_ARN"
    
    # Create Listener
    echo "Creating ALB Listener..."
    aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
        --region "$AWS_REGION" >/dev/null
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create ALB Listener"
        exit 1
    fi
    
    echo "ALB Listener created successfully"
    echo ""
    
    # Update service definition with load balancer
    sed -i "s|{{TARGET_GROUP_ARN}}|$TARGET_GROUP_ARN|g" ecs/service-definition.json
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
    echo ""
fi

# Create CloudWatch Log Group
echo "Creating CloudWatch Log Group..."
aws logs create-log-group --log-group-name "/ecs/clinicmanagementsystem" --region "$AWS_REGION" 2>/dev/null || echo "Log group already exists"
echo ""

# Replace placeholders in task definition
echo "Preparing task definition..."
sed -i "s|{{IMAGE_URI}}|$IMAGE_URI|g" ecs/task-definition.json
sed -i "s|{{AWS_REGION}}|$AWS_REGION|g" ecs/task-definition.json
sed -i "s|{{ACCOUNT_ID}}|$ACCOUNT_ID|g" ecs/task-definition.json
sed -i "s|{{DB_CONNECTION_STRING}}|$DB_CONNECTION_STRING|g" ecs/task-definition.json
sed -i "s|{{REDIS_CONNECTION_STRING}}|$REDIS_CONNECTION_STRING|g" ecs/task-definition.json

# Register task definition
echo "Registering ECS task definition..."
TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file://ecs/task-definition.json \
    --region "$AWS_REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to register task definition"
    exit 1
fi

echo "Task definition registered: $TASK_DEF_ARN"
echo ""

# Replace placeholders in service definition
echo "Preparing service definition..."
sed -i "s|{{CLUSTER_NAME}}|$CLUSTER_NAME|g" ecs/service-definition.json
sed -i "s|{{SUBNET_1}}|$SUBNET_1|g" ecs/service-definition.json
sed -i "s|{{SUBNET_2}}|$SUBNET_2|g" ecs/service-definition.json
sed -i "s|{{SECURITY_GROUP}}|$SECURITY_GROUP|g" ecs/service-definition.json

# Check if service exists
SERVICE_NAME="clinicmanagementsystem-service"
echo "Checking if ECS service exists..."
EXISTING_SERVICE=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[?status==`ACTIVE`].serviceName' \
    --output text 2>/dev/null)

if [ -z "$EXISTING_SERVICE" ] || [ "$EXISTING_SERVICE" == "None" ]; then
    # Create new service
    echo "Creating new ECS service..."
    aws ecs create-service \
        --cli-input-json file://ecs/service-definition.json \
        --region "$AWS_REGION" >/dev/null
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create ECS service"
        exit 1
    fi
    
    echo "ECS service created successfully"
else
    # Update existing service
    echo "Updating existing ECS service..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --task-definition "$TASK_DEF_ARN" \
        --force-new-deployment \
        --region "$AWS_REGION" >/dev/null
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to update ECS service"
        exit 1
    fi
    
    echo "ECS service updated successfully"
fi

echo ""

# Wait for service to stabilize
echo "Waiting for service to become stable (this may take a few minutes)..."
aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION"

if [ $? -ne 0 ]; then
    echo "WARNING: Service did not stabilize within the expected time"
    echo "Check the ECS console for more details"
else
    echo "Service is stable"
fi

echo ""

# Display deployment information
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo "Task Definition: $TASK_DEF_ARN"
echo "Region: $AWS_REGION"

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
    echo "Load Balancer DNS: $ALB_DNS"
    echo "Application URL: http://$ALB_DNS"
fi

echo "CloudWatch Logs: /ecs/clinicmanagementsystem"
echo ""

# Verify deployment
echo "Verifying deployment..."
aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[0].[serviceName,status,runningCount,desiredCount]' \
    --output table

echo ""
echo "=========================================="
echo "Deployment Completed Successfully!"
echo "=========================================="
echo ""
echo "To view logs:"
echo "aws logs tail /ecs/clinicmanagementsystem --follow --region $AWS_REGION"
echo ""
echo "To check service status:"
echo "aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
echo ""
