param(
    [string]$ApiBaseUrl = "https://study-app-b0xq.onrender.com",
    [string]$GoogleClientId = $env:GOOGLE_CLIENT_ID,
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
    firebase deploy --only hosting --project $ProjectId
    if ($LASTEXITCODE -ne 0) {
        throw "Firebase deploy failed with exit code $LASTEXITCODE."
    }

    Write-Host "Deployment completed successfully!" -ForegroundColor Green
    Write-Host "Live URL: https://$ProjectId.web.app" -ForegroundColor Cyan
}
finally {
    Pop-Location
}
