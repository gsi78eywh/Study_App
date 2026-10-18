# StudyApp - Firebase Hosting Build & Deploy
param(
    [string]$ApiBaseUrl = "https://study-app-b0xq.onrender.com",
    [string]$GoogleClientId = $(if ($env:GOOGLE_CLIENT_ID) { $env:GOOGLE_CLIENT_ID } else { "717073834269-9tegppvpc37rd197rmjpkabc108rb9uj.apps.googleusercontent.com" }),
    [string]$ProjectId = "studyapp-51772",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
# Ensure Firebase CLI runs in interactive browser mode rather than non-interactive agent mode
Remove-Item Env:\ANTIGRAVITY_AGENT -ErrorAction SilentlyContinue

function Invoke-FirebaseCli {
    param([string[]]$Arguments)
    $cachedFirebaseJs = "$env:LOCALAPPDATA\npm-cache\_npx\7750544ccf494d8b\node_modules\firebase-tools\lib\bin\firebase.js"
    if (Get-Command firebase -ErrorAction SilentlyContinue) {
        & firebase @Arguments
    } elseif ((Test-Path "$env:USERPROFILE\node.exe") -and (Test-Path $cachedFirebaseJs)) {
        & "$env:USERPROFILE\node.exe" $cachedFirebaseJs @Arguments
    } elseif (Get-Command npx -ErrorAction SilentlyContinue) {
        & npx firebase-tools @Arguments
    } elseif (Test-Path "$env:USERPROFILE\npx.ps1") {
        & "$env:USERPROFILE\npx.ps1" firebase-tools @Arguments
    } else {
        throw "Firebase CLI ('firebase' or 'npx firebase-tools') was not found."
    }
}

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  StudyApp - Firebase Hosting Build & Deploy" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Target API: $ApiBaseUrl" -ForegroundColor Cyan
Write-Host "Target Firebase Project: $ProjectId" -ForegroundColor Cyan
Write-Host ""

# 1. Check Firebase Auth
Write-Host "[1/3] Checking Firebase authentication..." -ForegroundColor Yellow
$ErrorActionPreference = "Continue"
$loginCheck = Invoke-FirebaseCli @("login:list") 2>&1 | Out-String
$ErrorActionPreference = "Stop"
if ($LASTEXITCODE -ne 0 -or ($loginCheck -match "No authorized accounts")) {
    Write-Host "[!] Not logged in. Opening browser for Firebase authentication..." -ForegroundColor Magenta
    $ErrorActionPreference = "Continue"
    Invoke-FirebaseCli @("login")
    $loginExit = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    if ($loginExit -ne 0) {
        Write-Error "Firebase login failed or cancelled."
    }
}
Write-Host "[OK] Firebase is authenticated." -ForegroundColor Green
Write-Host ""

# 2. Build Flutter Web
if ($SkipBuild -and (Test-Path "$PSScriptRoot\mobile\build\web\main.dart.js")) {
    Write-Host "[2/3] Using existing Flutter Web build in mobile/build/web..." -ForegroundColor Green
    Write-Host ""
} else {
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
}

# 3. Deploy to Firebase Hosting
Write-Host "[3/3] Deploying to Firebase Hosting ($ProjectId)..." -ForegroundColor Yellow
Invoke-FirebaseCli @("deploy", "--only", "hosting", "--project", $ProjectId)
if ($LASTEXITCODE -ne 0) {
    Write-Error "Firebase deployment failed."
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "  Deployment Complete!" -ForegroundColor Green
Write-Host "  Live URL: https://$ProjectId.web.app" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Green
