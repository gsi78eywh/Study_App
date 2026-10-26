<#
.SYNOPSIS
    Deploys the StudyApp .NET 10 Backend API to Google Cloud Run and optionally builds the Flutter APK pointed to the Cloud Run endpoint.
.DESCRIPTION
    Eliminates Render free-tier cold-start delays and network timeouts by deploying to Google Cloud Run
    in asia-southeast1 (Singapore, low latency for Philippines/APAC students) with CPU boost and concurrency=80.
#>
param(
    [string]$ProjectId = "studyapp-51772",
    [string]$Region = "asia-southeast1",
    [string]$ServiceName = "studyapp-api",
    [switch]$BuildApk
)

$ErrorActionPreference = "Stop"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  StudyApp -> Google Cloud Run Deployment ($ProjectId)" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    Write-Error "Google Cloud SDK (gcloud) is not installed or not on PATH. Install from https://cloud.google.com/sdk"
}

Write-Host "[1/4] Setting active GCP project to $ProjectId..." -ForegroundColor Yellow
gcloud config set project $ProjectId
gcloud config set run/region $Region

Write-Host "[2/4] Building & deploying container to Google Cloud Run ($Region)..." -ForegroundColor Yellow
gcloud run deploy $ServiceName `
    --source . `
    --region $Region `
    --platform managed `
    --allow-unauthenticated `
    --port 8080 `
    --cpu 2 `
    --memory 1Gi `
    --concurrency 80 `
    --min-instances 1 `
    --max-instances 10 `
    --cpu-boost `
    --timeout 120s `
    --set-env-vars "ASPNETCORE_ENVIRONMENT=Production,DOTNET_TieredPGO=1"

$CloudRunUrl = (gcloud run services describe $ServiceName --region $Region --format "value(status.url)").Trim()
Write-Host "[3/4] Deployed successfully! Live Cloud Run URL: $CloudRunUrl" -ForegroundColor Green

Write-Host "[4/4] Verifying /health endpoint..." -ForegroundColor Yellow
try {
    $Health = Invoke-RestMethod -Uri "$CloudRunUrl/health" -TimeoutSec 10
    Write-Host "Health check passed: $($Health | ConvertTo-Json -Compress)" -ForegroundColor Green
} catch {
    Write-Warning "Health check returned warning: $($_.Exception.Message)"
}

if ($BuildApk -and $CloudRunUrl) {
    Write-Host "Building Android Release APK bound to Cloud Run URL ($CloudRunUrl)..." -ForegroundColor Cyan
    Push-Location "$PSScriptRoot\mobile"
    try {
        flutter build apk --release --dart-define="API_BASE_URL=$CloudRunUrl" --dart-define="CLOUD_RUN_URL=$CloudRunUrl"
        Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "$PSScriptRoot\StudyApp-release.apk" -Force
        Write-Host "APK built and copied to $PSScriptRoot\StudyApp-release.apk" -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

