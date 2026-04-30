# Clinic Management System - .NET 8

## Overview
This is a modern Clinic Management System migrated from ASP.NET Web Forms 4.5.2 to .NET 8 using clean architecture principles.

## Architecture
The solution follows clean architecture with the following layers:

### Domain Layer (`ClinicManagement.Domain`)
- Contains domain entities (Patient, Doctor, Department, Appointment, Bill, Staff, TimeSlot)
- Contains domain interfaces
- Contains enums and value objects
- No dependencies on other layers

### Application Layer (`ClinicManagement.Application`)
- Contains business logic and services
- Contains DTOs (Data Transfer Objects)
- Contains AutoMapper profiles
- Contains FluentValidation validators
- Depends only on Domain layer

### Infrastructure Layer (`ClinicManagement.Infrastructure`)
- Contains EF Core DbContext
- Contains repository implementations
- Contains data access logic
- Depends on Domain and Application layers

### Web Layer (`ClinicManagement.Web`)
- ASP.NET Core Razor Pages application
- Contains UI pages and view models
- Contains Program.cs for application startup
- Depends on Infrastructure and Application layers

## Prerequisites
- .NET 8 SDK
- SQL Server (LocalDB or Express)
- Visual Studio 2022 or VS Code

## Setup Instructions

### 1. Database Setup
The application uses SQL Server with the following connection string (configured in `appsettings.json`):
```
Data Source=.\\SQLEXPRESS;Initial Catalog=DBProject;Integrated Security=True;TrustServerCertificate=True
```

### 2. Restore Packages
```bash
cd /modernize-data/studio-data/TNT1001/APP215000/transformed-code/441/studio-workspace/Newrpochecktest
dotnet restore
```

### 3. Build the Solution
```bash
dotnet build
```

### 4. Run the Application
```bash
cd src/ClinicManagement.Web
dotnet run
```

The application will be available at `https://localhost:5001` or `http://localhost:5000`

## Migration Notes

### What Was Migrated
- **Web Forms Pages** → Razor Pages
- **Master Pages** → Layout Pages (`_Layout.cshtml`)
- **Code-Behind** → Page Models (`.cshtml.cs`)
- **ADO.NET with Stored Procedures** → Entity Framework Core 8.0
- **Web.config** → appsettings.json
- **System.Web** → ASP.NET Core equivalents
- **Session State** → ASP.NET Core Session with distributed cache

### Key Changes
1. **Data Access**: Migrated from ADO.NET with stored procedures to EF Core with LINQ
2. **Configuration**: Moved from Web.config to appsettings.json
3. **Dependency Injection**: Using built-in ASP.NET Core DI container
4. **Logging**: Migrated to Serilog for structured logging
5. **Authentication**: Ready for ASP.NET Core Identity (to be implemented)

### Package Updates
- **Entity Framework 6.x** → **Microsoft.EntityFrameworkCore 8.0.0**
- **Microsoft.AspNetCore.App 6.0** → **Microsoft.AspNetCore.App 8.0**
- Added **Serilog.AspNetCore 8.0.0** for logging
- Added **AutoMapper 12.0.1** for object mapping
- Added **FluentValidation 11.9.0** for validation

## Project Structure
```
ClinicManagement/
├── src/
│   ├── ClinicManagement.Domain/
│   │   ├── Entities/
│   │   ├── Interfaces/
│   │   ├── Enums/
│   │   └── Exceptions/
│   ├── ClinicManagement.Application/
│   │   ├── Services/
│   │   ├── DTOs/
│   │   ├── Mappings/
│   │   └── Extensions/
│   ├── ClinicManagement.Infrastructure/
│   │   ├── Data/
│   │   ├── Repositories/
│   │   └── Extensions/
│   └── ClinicManagement.Web/
│       ├── Pages/
│       ├── wwwroot/
│       ├── Program.cs
│       └── appsettings.json
├── tests/
│   ├── ClinicManagement.UnitTests/
│   └── ClinicManagement.IntegrationTests/
└── ClinicManagement.sln
```

## Testing
Run unit tests:
```bash
dotnet test tests/ClinicManagement.UnitTests
```

Run integration tests:
```bash
dotnet test tests/ClinicManagement.IntegrationTests
```

## Known Issues
1. Database migrations need to be created and applied
2. Authentication/Authorization needs to be implemented
3. Some stored procedures may need to be converted to EF Core queries
4. UI styling needs to be updated to match original design

## Future Improvements
1. Implement ASP.NET Core Identity for authentication
2. Add API endpoints for mobile/external access
3. Implement real-time notifications using SignalR
4. Add comprehensive unit and integration tests
5. Implement caching strategies
6. Add API documentation with Swagger

## Support
For issues or questions, please contact the development team.
