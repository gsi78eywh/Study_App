# Stage 1: Build (Google Cloud Run & Container Deployment)
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
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

# Stage 2: Runtime (Optimized for Google Cloud Run port 8080 & low cold-start latency)
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends tesseract-ocr tesseract-ocr-eng && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /app/data /app/data/data-protection-keys
COPY --from=build /app/publish .

# Google Cloud Run injects PORT (default 8080). Program.cs binds http://0.0.0.0:${PORT}.
ENV PORT=8080
ENV ASPNETCORE_URLS=http://0.0.0.0:8080
ENV ASPNETCORE_ENVIRONMENT=Production
ENV DOTNET_EnableDiagnostics=0
ENV DOTNET_TieredPGO=1
ENV ConnectionStrings__DefaultConnection="Data Source=/app/data/studyapp.db"
ENV DATA_PROTECTION_KEY_PATH=/app/data/data-protection-keys
EXPOSE 8080

ENTRYPOINT ["dotnet", "StudyApp.Api.dll"]
