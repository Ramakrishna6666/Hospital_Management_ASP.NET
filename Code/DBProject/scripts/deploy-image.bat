@echo off
setlocal enabledelayedexpansion

REM AWS ECS Fargate Deployment Script for DBProject (Windows)
REM This script deploys the containerized application to AWS ECS Fargate

echo ==========================================
echo AWS ECS Fargate Deployment Script
echo ==========================================
echo.

REM Prompt for AWS configuration
set /p AWS_REGION="Enter AWS region (e.g., us-east-1): "
set /p CLUSTER_NAME="Enter ECS cluster name (e.g., dbproject-cluster): "
set /p VPC_ID="Enter VPC ID (e.g., vpc-0abc123def456): "
set /p SUBNETS_INPUT="Enter Subnet IDs comma-separated (e.g., subnet-0abc123,subnet-0def456): "
set /p SECURITY_GROUP="Enter Security Group ID (e.g., sg-0abc123def): "
set /p IMAGE_URI="Enter Docker image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/dbproject:latest): "

REM Parse subnets
for /f "tokens=1,2 delims=," %%a in ("!SUBNETS_INPUT!") do (
    set SUBNET_1=%%a
    set SUBNET_2=%%b
)
if "!SUBNET_2!"=="" set SUBNET_2=!SUBNET_1!

REM Get AWS Account ID
echo.
echo Retrieving AWS Account ID...
for /f "delims=" %%a in ('aws sts get-caller-identity --query Account --output text') do set ACCOUNT_ID=%%a
echo AWS Account ID: !ACCOUNT_ID!

REM Database configuration
echo.
echo === Database Configuration ===
set /p DB_HOST="Enter Database Host (e.g., mydb.abc123.us-east-1.rds.amazonaws.com): "
set /p DB_USER="Enter Database User: "
set /p DB_PASSWORD="Enter Database Password: "

REM Check if ECS cluster exists, create if not
echo.
echo Checking ECS cluster...
aws ecs describe-clusters --clusters "!CLUSTER_NAME!" --region "!AWS_REGION!" >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Creating ECS cluster: !CLUSTER_NAME!
    aws ecs create-cluster --cluster-name "!CLUSTER_NAME!" --region "!AWS_REGION!"
) else (
    echo ECS cluster already exists: !CLUSTER_NAME!
)

REM Ask about load balancer
echo.
set /p NEED_LB="Do you need a load balancer for this service? (y/n): "

if /i "!NEED_LB!"=="y" (
    echo.
    echo === Creating Application Load Balancer ===
    
    set ALB_NAME=dbproject-alb
    echo Creating Application Load Balancer: !ALB_NAME!
    
    for /f "delims=" %%a in ('aws elbv2 create-load-balancer --name "!ALB_NAME!" --subnets "!SUBNET_1!" "!SUBNET_2!" --security-groups "!SECURITY_GROUP!" --scheme internet-facing --type application --ip-address-type ipv4 --region "!AWS_REGION!" --query "LoadBalancers[0].LoadBalancerArn" --output text 2^>nul') do set ALB_ARN=%%a
    
    if "!ALB_ARN!"=="" (
        echo Load balancer may already exist, retrieving ARN...
        for /f "delims=" %%a in ('aws elbv2 describe-load-balancers --names "!ALB_NAME!" --region "!AWS_REGION!" --query "LoadBalancers[0].LoadBalancerArn" --output text') do set ALB_ARN=%%a
    )
    
    echo Load Balancer ARN: !ALB_ARN!
    
    REM Get ALB DNS name
    for /f "delims=" %%a in ('aws elbv2 describe-load-balancers --load-balancer-arns "!ALB_ARN!" --region "!AWS_REGION!" --query "LoadBalancers[0].DNSName" --output text') do set ALB_DNS=%%a
    
    REM Create Target Group
    set TG_NAME=dbproject-tg
    echo Creating Target Group: !TG_NAME!
    
    for /f "delims=" %%a in ('aws elbv2 create-target-group --name "!TG_NAME!" --protocol HTTP --port 80 --vpc-id "!VPC_ID!" --target-type ip --health-check-enabled --health-check-protocol HTTP --health-check-path "/" --health-check-interval-seconds 30 --health-check-timeout-seconds 5 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region "!AWS_REGION!" --query "TargetGroups[0].TargetGroupArn" --output text 2^>nul') do set TARGET_GROUP_ARN=%%a
    
    if "!TARGET_GROUP_ARN!"=="" (
        echo Target group may already exist, retrieving ARN...
        for /f "delims=" %%a in ('aws elbv2 describe-target-groups --names "!TG_NAME!" --region "!AWS_REGION!" --query "TargetGroups[0].TargetGroupArn" --output text') do set TARGET_GROUP_ARN=%%a
    )
    
    echo Target Group ARN: !TARGET_GROUP_ARN!
    
    REM Create Listener
    echo Creating ALB Listener...
    aws elbv2 create-listener --load-balancer-arn "!ALB_ARN!" --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn="!TARGET_GROUP_ARN!" --region "!AWS_REGION!" 2>nul
    
    REM Update service definition with load balancer
    powershell -command "(Get-Content ecs\service-definition.json) -replace '{{TARGET_GROUP_ARN}}', '!TARGET_GROUP_ARN!' | Set-Content ecs\service-definition.json"
) else (
    echo Skipping load balancer creation
    REM Remove loadBalancers section from service definition
    powershell -command "$json = Get-Content ecs\service-definition.json | ConvertFrom-Json; $json.PSObject.Properties.Remove('loadBalancers'); $json.PSObject.Properties.Remove('healthCheckGracePeriodSeconds'); $json | ConvertTo-Json -Depth 10 | Set-Content ecs\service-definition.json"
)

REM Create CloudWatch Log Group
echo.
echo Creating CloudWatch Log Group...
aws logs create-log-group --log-group-name "/ecs/dbproject" --region "!AWS_REGION!" 2>nul

REM Replace placeholders in task definition
echo.
echo Preparing task definition...
powershell -command "(Get-Content ecs\task-definition.json) -replace '{{IMAGE_URI}}', '!IMAGE_URI!' -replace '{{AWS_REGION}}', '!AWS_REGION!' -replace '{{ACCOUNT_ID}}', '!ACCOUNT_ID!' -replace '{{DB_HOST}}', '!DB_HOST!' -replace '{{DB_USER}}', '!DB_USER!' -replace '{{DB_PASSWORD}}', '!DB_PASSWORD!' | Set-Content ecs\task-definition.json"

REM Register task definition
echo Registering ECS task definition...
for /f "delims=" %%a in ('aws ecs register-task-definition --cli-input-json file://ecs/task-definition.json --region "!AWS_REGION!" --query "taskDefinition.taskDefinitionArn" --output text') do set TASK_DEF_ARN=%%a

echo Task Definition ARN: !TASK_DEF_ARN!

REM Replace placeholders in service definition
echo.
echo Preparing service definition...
powershell -command "(Get-Content ecs\service-definition.json) -replace '{{CLUSTER_NAME}}', '!CLUSTER_NAME!' -replace '{{SUBNET_1}}', '!SUBNET_1!' -replace '{{SUBNET_2}}', '!SUBNET_2!' -replace '{{SECURITY_GROUP}}', '!SECURITY_GROUP!' | Set-Content ecs\service-definition.json"

REM Check if service exists
echo Checking if ECS service exists...
for /f "delims=" %%a in ('aws ecs describe-services --cluster "!CLUSTER_NAME!" --services "dbproject-service" --region "!AWS_REGION!" --query "services[0].serviceName" --output text 2^>nul') do set SERVICE_EXISTS=%%a

if "!SERVICE_EXISTS!"=="None" (
    echo Creating new ECS service...
    aws ecs create-service --cli-input-json file://ecs/service-definition.json --region "!AWS_REGION!"
) else (
    echo Updating existing ECS service...
    aws ecs update-service --cluster "!CLUSTER_NAME!" --service "dbproject-service" --task-definition "!TASK_DEF_ARN!" --desired-count 2 --force-new-deployment --region "!AWS_REGION!"
)

REM Wait for service to stabilize
echo.
echo Waiting for service to become stable (this may take a few minutes)...
aws ecs wait services-stable --cluster "!CLUSTER_NAME!" --services "dbproject-service" --region "!AWS_REGION!"

REM Display deployment status
echo.
echo ==========================================
echo Deployment Completed Successfully!
echo ==========================================
echo.
echo Service Details:
aws ecs describe-services --cluster "!CLUSTER_NAME!" --services "dbproject-service" --region "!AWS_REGION!" --query "services[0].[serviceName,status,runningCount,desiredCount]" --output table

if /i "!NEED_LB!"=="y" (
    echo.
    echo Application URL: http://!ALB_DNS!
    echo.
    echo Note: It may take a few minutes for the load balancer to become healthy.
)

echo.
echo CloudWatch Logs: /ecs/dbproject
echo Region: !AWS_REGION!
echo.
echo To view logs:
echo aws logs tail /ecs/dbproject --follow --region !AWS_REGION!
echo.

endlocal
