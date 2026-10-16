# StudyApp - Firebase Hosting Build & Deploy
param(
    [string]$ApiBaseUrl = "https://study-app-b0xq.onrender.com",
    [string]$GoogleClientId = $env:GOOGLE_CLIENT_ID,
    [string]$ProjectId = "studyapp-51772"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  StudyApp - Firebase Hosting Build & Deploy" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Target API: $ApiBaseUrl" -ForegroundColor Cyan
Write-Host "Target Firebase Project: $ProjectId" -ForegroundColor Cyan
Write-Host ""

# 1. Check Firebase Auth
Write-Host "[1/3] Checking Firebase authentication..." -ForegroundColor Yellow
$loginCheck = & firebase login:list 2>&1
if ($LASTEXITCODE -ne 0 -or ($loginCheck -match "No authorized accounts")) {
    Write-Host "[!] Not logged in. Starting 'firebase login'..." -ForegroundColor Magenta
    & firebase login
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Firebase login failed or cancelled."
    }
}
Write-Host "[OK] Firebase is authenticated." -ForegroundColor Green
Write-Host ""

# 2. Build Flutter Web
Write-Host "[2/3] Building Flutter Web (Release)..." -ForegroundColor Yellow
Push-Location "$PSScriptRoot\mobile"
try {
    $buildArgs = @("build", "web", "--release", "--dart-define=API_BASE_URL=$($ApiBaseUrl.TrimEnd('/'))")
    if (-not [string]::IsNullOrWhiteSpace($GoogleClientId)) {
        Write-Host "Embedding Google Client ID: $GoogleClientId" -ForegroundColor Green
        $buildArgs += "--dart-define=GOOGLE_CLIENT_ID=$GoogleClientId"
    } else {
        Write-Host "[NOTE] GoogleClientId not specified. Standard authentication will be used." -ForegroundColor Yellow
    }

    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter web build failed."
    }
} finally {
    Pop-Location
}
Write-Host "[OK] Web build compiled into mobile/build/web." -ForegroundColor Green
Write-Host ""

# 3. Deploy to Firebase Hosting
Write-Host "[3/3] Deploying to Firebase Hosting ($ProjectId)..." -ForegroundColor Yellow
& firebase deploy --only hosting --project $ProjectId
if ($LASTEXITCODE -ne 0) {
    Write-Error "Firebase deployment failed."
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "  Deployment Complete!" -ForegroundColor Green
Write-Host "  Live URL: https://$ProjectId.web.app" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Green
