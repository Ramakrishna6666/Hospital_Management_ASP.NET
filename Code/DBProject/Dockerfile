# Multi-stage Dockerfile for ASP.NET Framework 4.5.2 Application
# This application requires Windows containers

# Build stage
FROM mcr.microsoft.com/dotnet/framework/sdk:4.8 AS builder

WORKDIR /app

# Copy project files for dependency restoration
COPY *.csproj ./
COPY *.sln ./
COPY packages.config ./

# Restore NuGet packages
RUN nuget restore DBProject.sln

# Copy all source code
COPY . ./

# Build the application in Release mode
RUN msbuild DBProject.csproj /p:Configuration=Release /p:OutputPath=C:\publish /p:DeployOnBuild=true /p:WebPublishMethod=FileSystem /p:publishUrl=C:\publish

# Runtime stage
FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8

WORKDIR /inetpub/wwwroot

# Copy published application from builder stage
COPY --from=builder C:/publish .

# Configure IIS application pool settings for better performance
RUN powershell -Command \
    Import-Module WebAdministration; \
    Set-ItemProperty 'IIS:\AppPools\DefaultAppPool' -Name processModel.idleTimeout -Value ([TimeSpan]::FromMinutes(0)); \
    Set-ItemProperty 'IIS:\AppPools\DefaultAppPool' -Name recycling.periodicRestart.time -Value ([TimeSpan]::FromMinutes(0))

# Expose port 80 for HTTP traffic
EXPOSE 80

# Health check endpoint (basic IIS check)
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD powershell -command "try { \$response = Invoke-WebRequest -Uri http://localhost:80 -UseBasicParsing -TimeoutSec 5; if (\$response.StatusCode -eq 200) { exit 0 } else { exit 1 } } catch { exit 1 }"

# IIS will automatically start with the container
