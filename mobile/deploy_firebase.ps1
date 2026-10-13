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

Push-Location $PSScriptRoot
try {
    $buildArgs = @("build", "web", "--release", "--dart-define=API_BASE_URL=$($ApiBaseUrl.TrimEnd('/'))")
    if ([string]::IsNullOrWhiteSpace($GoogleClientId)) {
        throw "GoogleClientId is required for Google sign-in. Use the OAuth Web client ID ending in .apps.googleusercontent.com."
    }
    $buildArgs += "--dart-define=GOOGLE_CLIENT_ID=$GoogleClientId"
    flutter @buildArgs
    firebase deploy --only hosting --project studyapp-51772
}
finally {
    Pop-Location
}
