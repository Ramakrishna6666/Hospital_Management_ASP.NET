@echo off
setlocal enabledelayedexpansion

REM Deploy Docker Image to AWS ECS Fargate
REM Clinic Management System Deployment Script

echo ==========================================
echo AWS ECS Fargate Deployment Script
echo Clinic Management System
echo ==========================================
echo.

REM Prompt for AWS configuration
echo === AWS Configuration ===
set /p AWS_REGION="Enter AWS Region (e.g., us-east-1): "
set /p CLUSTER_NAME="Enter ECS Cluster Name (e.g., clinic-cluster): "
echo.

REM Get AWS Account ID
echo Retrieving AWS Account ID...
for /f "delims=" %%i in ('aws sts get-caller-identity --query Account --output text') do set ACCOUNT_ID=%%i
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to retrieve AWS Account ID. Please check AWS CLI configuration.
    exit /b 1
)
echo AWS Account ID: !ACCOUNT_ID!
echo.

REM Prompt for network configuration
echo === Network Configuration ===
set /p VPC_ID="Enter VPC ID (e.g., vpc-0abc123def456): "
set /p SUBNETS_INPUT="Enter Subnet IDs comma-separated (e.g., subnet-0abc123,subnet-0def456): "
set /p SECURITY_GROUP="Enter Security Group ID (e.g., sg-0abc123def): "
echo.

REM Parse subnets
for /f "tokens=1,2 delims=," %%a in ("!SUBNETS_INPUT!") do (
    set SUBNET_1=%%a
    set SUBNET_2=%%b
)
if "!SUBNET_2!"=="" set SUBNET_2=!SUBNET_1!

REM Prompt for Docker image URI
echo === Docker Image Configuration ===
set /p IMAGE_URI="Enter Docker Image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/clinicmanagementsystem:latest): "
echo.

REM Prompt for database configuration
echo === Database Configuration ===
set /p DB_CONNECTION_STRING="Enter Database Connection String: "
set /p REDIS_CONNECTION_STRING="Enter Redis Connection String (optional, press Enter to skip): "
echo.

REM Check if ECS cluster exists, create if not
echo Checking if ECS cluster exists...
aws ecs describe-clusters --clusters !CLUSTER_NAME! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Cluster does not exist. Creating ECS cluster...
    aws ecs create-cluster --cluster-name !CLUSTER_NAME! --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECS cluster
        exit /b 1
    )
    echo ECS cluster created successfully
)
echo.

REM Prompt for load balancer configuration
echo === Load Balancer Configuration ===
set /p NEED_LB="Do you need a load balancer for this service? (y/n): "
echo.

if /i "!NEED_LB!"=="y" (
    echo Creating Application Load Balancer and Target Group...
    
    REM Create Application Load Balancer
    set ALB_NAME=clinic-alb-%RANDOM%
    echo Creating ALB: !ALB_NAME!
    for /f "delims=" %%i in ('aws elbv2 create-load-balancer --name !ALB_NAME! --subnets !SUBNET_1! !SUBNET_2! --security-groups !SECURITY_GROUP! --scheme internet-facing --type application --ip-address-type ipv4 --region !AWS_REGION! --query "LoadBalancers[0].LoadBalancerArn" --output text') do set ALB_ARN=%%i
    
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create Application Load Balancer
        exit /b 1
    )
    
    echo ALB created: !ALB_ARN!
    
    REM Get ALB DNS name
    for /f "delims=" %%i in ('aws elbv2 describe-load-balancers --load-balancer-arns !ALB_ARN! --region !AWS_REGION! --query "LoadBalancers[0].DNSName" --output text') do set ALB_DNS=%%i
    
    REM Create Target Group with target-type ip
    set TG_NAME=clinic-tg-%RANDOM%
    echo Creating Target Group: !TG_NAME!
    for /f "delims=" %%i in ('aws elbv2 create-target-group --name !TG_NAME! --protocol HTTP --port 80 --vpc-id !VPC_ID! --target-type ip --health-check-enabled --health-check-protocol HTTP --health-check-path "/Helpers/HealthCheckHandler.ashx" --health-check-interval-seconds 30 --health-check-timeout-seconds 5 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region !AWS_REGION! --query "TargetGroups[0].TargetGroupArn" --output text') do set TARGET_GROUP_ARN=%%i
    
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create Target Group
        exit /b 1
    )
    
    echo Target Group created: !TARGET_GROUP_ARN!
    
    REM Create Listener
    echo Creating ALB Listener...
    aws elbv2 create-listener --load-balancer-arn !ALB_ARN! --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=!TARGET_GROUP_ARN! --region !AWS_REGION! >nul
    
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ALB Listener
        exit /b 1
    )
    
    echo ALB Listener created successfully
    echo.
    
    REM Update service definition with load balancer
    powershell -Command "(Get-Content ecs\service-definition.json) -replace '{{TARGET_GROUP_ARN}}', '!TARGET_GROUP_ARN!' | Set-Content ecs\service-definition.json"
) else (
    echo Skipping load balancer creation
    REM Remove loadBalancers section from service definition
    powershell -Command "$json = Get-Content ecs\service-definition.json | ConvertFrom-Json; $json.PSObject.Properties.Remove('loadBalancers'); $json.PSObject.Properties.Remove('healthCheckGracePeriodSeconds'); $json | ConvertTo-Json -Depth 10 | Set-Content ecs\service-definition.json"
    echo.
)

REM Create CloudWatch Log Group
echo Creating CloudWatch Log Group...
aws logs create-log-group --log-group-name "/ecs/clinicmanagementsystem" --region !AWS_REGION! 2>nul
echo.

REM Replace placeholders in task definition
echo Preparing task definition...
powershell -Command "(Get-Content ecs\task-definition.json) -replace '{{IMAGE_URI}}', '!IMAGE_URI!' -replace '{{AWS_REGION}}', '!AWS_REGION!' -replace '{{ACCOUNT_ID}}', '!ACCOUNT_ID!' -replace '{{DB_CONNECTION_STRING}}', '!DB_CONNECTION_STRING!' -replace '{{REDIS_CONNECTION_STRING}}', '!REDIS_CONNECTION_STRING!' | Set-Content ecs\task-definition.json"

REM Register task definition
echo Registering ECS task definition...
for /f "delims=" %%i in ('aws ecs register-task-definition --cli-input-json file://ecs/task-definition.json --region !AWS_REGION! --query "taskDefinition.taskDefinitionArn" --output text') do set TASK_DEF_ARN=%%i

if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to register task definition
    exit /b 1
)

echo Task definition registered: !TASK_DEF_ARN!
echo.

REM Replace placeholders in service definition
echo Preparing service definition...
powershell -Command "(Get-Content ecs\service-definition.json) -replace '{{CLUSTER_NAME}}', '!CLUSTER_NAME!' -replace '{{SUBNET_1}}', '!SUBNET_1!' -replace '{{SUBNET_2}}', '!SUBNET_2!' -replace '{{SECURITY_GROUP}}', '!SECURITY_GROUP!' | Set-Content ecs\service-definition.json"

REM Check if service exists
set SERVICE_NAME=clinicmanagementsystem-service
echo Checking if ECS service exists...
for /f "delims=" %%i in ('aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[?status==`ACTIVE`].serviceName" --output text 2^>nul') do set EXISTING_SERVICE=%%i

if "!EXISTING_SERVICE!"=="" (
    REM Create new service
    echo Creating new ECS service...
    aws ecs create-service --cli-input-json file://ecs/service-definition.json --region !AWS_REGION! >nul
    
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECS service
        exit /b 1
    )
    
    echo ECS service created successfully
) else (
    REM Update existing service
    echo Updating existing ECS service...
    aws ecs update-service --cluster !CLUSTER_NAME! --service !SERVICE_NAME! --task-definition !TASK_DEF_ARN! --force-new-deployment --region !AWS_REGION! >nul
    
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to update ECS service
        exit /b 1
    )
    
    echo ECS service updated successfully
)

echo.

REM Wait for service to stabilize
echo Waiting for service to become stable (this may take a few minutes)...
aws ecs wait services-stable --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION!

if !ERRORLEVEL! neq 0 (
    echo WARNING: Service did not stabilize within the expected time
    echo Check the ECS console for more details
) else (
    echo Service is stable
)

echo.

REM Display deployment information
echo ==========================================
echo Deployment Summary
echo ==========================================
echo Cluster: !CLUSTER_NAME!
echo Service: !SERVICE_NAME!
echo Task Definition: !TASK_DEF_ARN!
echo Region: !AWS_REGION!

if /i "!NEED_LB!"=="y" (
    echo Load Balancer DNS: !ALB_DNS!
    echo Application URL: http://!ALB_DNS!
)

echo CloudWatch Logs: /ecs/clinicmanagementsystem
echo.

REM Verify deployment
echo Verifying deployment...
aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[0].[serviceName,status,runningCount,desiredCount]" --output table

echo.
echo ==========================================
echo Deployment Completed Successfully!
echo ==========================================
echo.
echo To view logs:
echo aws logs tail /ecs/clinicmanagementsystem --follow --region !AWS_REGION!
echo.
echo To check service status:
echo aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION!
echo.

endlocal
