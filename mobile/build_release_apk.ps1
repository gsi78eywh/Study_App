param(
    [string]$ApiBaseUrl = "https://study-app-b0xq.onrender.com",
    [string]$GoogleClientId = $env:GOOGLE_CLIENT_ID
)

$ErrorActionPreference = "Stop"

if ($ApiBaseUrl -notmatch '^https://[^/]+/?$') {
    throw "ApiBaseUrl must be the HTTPS origin of your deployed API, for example https://study-app-b0xq.onrender.com."
}

$keyPropertiesPath = Join-Path $PSScriptRoot "android/key.properties"
if (-not (Test-Path -LiteralPath $keyPropertiesPath)) {
    throw "Release APKs need android/key.properties and a private Android signing keystore. Follow the Android release setup in README.md."
}

Write-Host "Building StudyApp Release APK..." -ForegroundColor Cyan
Write-Host "Target API: $ApiBaseUrl" -ForegroundColor Cyan

Push-Location $PSScriptRoot
try {
    $buildArgs = @("build", "apk", "--release", "--dart-define=API_BASE_URL=$($ApiBaseUrl.TrimEnd('/'))")
    if (-not [string]::IsNullOrWhiteSpace($GoogleClientId)) {
        Write-Host "Embedding Google Client ID: $GoogleClientId" -ForegroundColor Green
        $buildArgs += "--dart-define=GOOGLE_CLIENT_ID=$GoogleClientId"
    } else {
        Write-Host "[NOTE] GoogleClientId not specified. APK will support standard email/password authentication." -ForegroundColor Yellow
        Write-Host "       Pass -GoogleClientId 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com' to enable Google Sign-In." -ForegroundColor Yellow
    }

    flutter @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter APK compilation failed with exit code $LASTEXITCODE."
    }

    $outputPath = Join-Path $PSScriptRoot "build\app\outputs\flutter-apk\app-release.apk"
    Write-Host "Signed Release APK created successfully!" -ForegroundColor Green
    Write-Host "APK Location: $outputPath" -ForegroundColor Cyan
}
finally {
    Pop-Location
}
