param(
    [Parameter(Mandatory = $true)]
    [string]$ApiBaseUrl,
    [Parameter(Mandatory = $true)]
    [string]$GoogleClientId
)

$ErrorActionPreference = "Stop"

if ($ApiBaseUrl -notmatch '^https://[^/]+/?$') {
    throw "ApiBaseUrl must be the HTTPS origin of your deployed API, for example https://studyapp-api.onrender.com."
}

$keyPropertiesPath = Join-Path $PSScriptRoot "android/key.properties"
if (-not (Test-Path -LiteralPath $keyPropertiesPath)) {
    throw "Release APKs need android/key.properties and a private Android signing keystore. Follow the Android release setup in README.md."
}

Push-Location $PSScriptRoot
try {
    $buildArgs = @("build", "apk", "--release", "--dart-define=API_BASE_URL=$($ApiBaseUrl.TrimEnd('/'))")
    if ([string]::IsNullOrWhiteSpace($GoogleClientId)) {
        throw "GoogleClientId is required for Google sign-in. Use the OAuth Web client ID ending in .apps.googleusercontent.com."
    }
    $buildArgs += "--dart-define=GOOGLE_CLIENT_ID=$GoogleClientId"
    flutter @buildArgs
    Write-Host "APK: $PSScriptRoot\build\app\outputs\flutter-apk\app-release.apk"
}
finally {
    Pop-Location
}
