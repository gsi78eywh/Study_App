# Stage 1: Build
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy project files for optimal layer caching
COPY ["backend/src/StudyApp.Api/StudyApp.Api.csproj", "backend/src/StudyApp.Api/"]
COPY ["backend/src/StudyApp.Application/StudyApp.Application.csproj", "backend/src/StudyApp.Application/"]
COPY ["backend/src/StudyApp.Infrastructure/StudyApp.Infrastructure.csproj", "backend/src/StudyApp.Infrastructure/"]
COPY ["backend/src/StudyApp.Domain/StudyApp.Domain.csproj", "backend/src/StudyApp.Domain/"]

RUN dotnet restore "backend/src/StudyApp.Api/StudyApp.Api.csproj"

# Copy entire backend source
COPY backend/ backend/

# Publish release
WORKDIR "/src/backend/src/StudyApp.Api"
RUN dotnet publish "StudyApp.Api.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Stage 2: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .

# Create volume directory for SQLite database storage
RUN mkdir -p /app/data

# Default port configuration for Railway / Render
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "StudyApp.Api.dll"]
