# Dockerfile for ASP.NET Framework 4.5.2 Application
# Multi-stage build for Clinic Management System

# Build stage - Use .NET Framework SDK for building
FROM mcr.microsoft.com/dotnet/framework/sdk:4.8 AS builder

# Set working directory
WORKDIR /app

# Copy project files for dependency restoration
COPY *.csproj ./
COPY packages.config ./

# Restore NuGet packages
RUN nuget restore ClinicManagementSystem.csproj -PackagesDirectory ../packages

# Copy all source code
COPY . ./

# Build the application in Release mode
RUN msbuild ClinicManagementSystem.csproj /p:Configuration=Release /p:OutputPath=C:\publish /p:DeployOnBuild=true /p:WebPublishMethod=FileSystem /p:publishUrl=C:\publish

# Runtime stage - Use ASP.NET runtime image
FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8-windowsservercore-ltsc2019

# Set working directory
WORKDIR /inetpub/wwwroot

# Copy published application from builder stage
COPY --from=builder C:/publish .

# Expose port 80 for HTTP traffic
EXPOSE 80

# Configure IIS to use the application
# The base image already has IIS configured, just ensure the app is in the right location

# Health check endpoint (using the custom health check handler)
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD powershell -command "try { $response = Invoke-WebRequest -Uri http://localhost/Helpers/HealthCheckHandler.ashx -UseBasicParsing -TimeoutSec 5; if ($response.StatusCode -eq 200) { exit 0 } else { exit 1 } } catch { exit 1 }"

# Set environment variables
ENV ASPNET_ENVIRONMENT=Production

# IIS will automatically start with the container
