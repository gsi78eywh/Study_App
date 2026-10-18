param(
    [string]$ApiBaseUrl = "https://study-app-b0xq.onrender.com",
    [string]$GoogleClientId = $(if ($env:GOOGLE_CLIENT_ID) { $env:GOOGLE_CLIENT_ID } else { "717073834269-9tegppvpc37rd197rmjpkabc108rb9uj.apps.googleusercontent.com" }),
    [string]$ProjectId = "studyapp-51772"
)

$ErrorActionPreference = "Stop"

if ($ApiBaseUrl -notmatch '^https://[^/]+/?$') {
    throw "ApiBaseUrl must be the HTTPS origin of your deployed API, for example https://study-app-b0xq.onrender.com."
}

Write-Host "Deploying StudyApp Web to Firebase Hosting ($ProjectId)..." -ForegroundColor Cyan
Write-Host "Target API: $ApiBaseUrl" -ForegroundColor Cyan

Push-Location $PSScriptRoot
try {
    $buildArgs = @("build", "web", "--release", "--dart-define=API_BASE_URL=$($ApiBaseUrl.TrimEnd('/'))")
    if (-not [string]::IsNullOrWhiteSpace($GoogleClientId)) {
        Write-Host "Embedding Google Client ID: $GoogleClientId" -ForegroundColor Green
        $buildArgs += "--dart-define=GOOGLE_CLIENT_ID=$GoogleClientId"
    } else {
        Write-Host "[NOTE] GoogleClientId not specified. Web build will support standard email/password authentication." -ForegroundColor Yellow
        Write-Host "       Pass -GoogleClientId 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com' to enable Google Sign-In." -ForegroundColor Yellow
    }

    Write-Host "Compiling Flutter Web..." -ForegroundColor Yellow
    flutter @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter web compilation failed with exit code $LASTEXITCODE."
    }

    Write-Host "Deploying to Firebase Hosting..." -ForegroundColor Yellow
    if (Get-Command firebase -ErrorAction SilentlyContinue) {
        firebase deploy --only hosting --project $ProjectId
    } elseif (Get-Command npx -ErrorAction SilentlyContinue) {
        npx firebase-tools deploy --only hosting --project $ProjectId
    } elseif (Test-Path "$env:USERPROFILE\npx.ps1") {
        & "$env:USERPROFILE\npx.ps1" firebase-tools deploy --only hosting --project $ProjectId
    } else {
        throw "Firebase CLI ('firebase' or 'npx firebase-tools') was not found."
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Firebase deploy failed with exit code $LASTEXITCODE."
    }

    Write-Host "Deployment completed successfully!" -ForegroundColor Green
    Write-Host "Live URL: https://$ProjectId.web.app" -ForegroundColor Cyan
}
finally {
    Pop-Location
}
