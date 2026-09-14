# Stage 1: Build
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy project files for optimal layer caching
COPY ["src/StudyApp.Api/StudyApp.Api.csproj", "src/StudyApp.Api/"]
COPY ["src/StudyApp.Application/StudyApp.Application.csproj", "src/StudyApp.Application/"]
COPY ["src/StudyApp.Infrastructure/StudyApp.Infrastructure.csproj", "src/StudyApp.Infrastructure/"]
COPY ["src/StudyApp.Domain/StudyApp.Domain.csproj", "src/StudyApp.Domain/"]

RUN dotnet restore "src/StudyApp.Api/StudyApp.Api.csproj"

# Copy entire backend source
COPY . .

# Publish release
WORKDIR "/src/src/StudyApp.Api"
RUN dotnet publish "StudyApp.Api.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Stage 2: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .

# Create volume directory for SQLite database storage
RUN mkdir -p /app/data

# Default port configuration for Railway / Render
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "StudyApp.Api.dll"]
