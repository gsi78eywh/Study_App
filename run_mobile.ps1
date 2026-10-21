# Run the Flutter mobile app from the repository root
param(
    [string]$Device = "",
    [string]$ApiBaseUrl = "http://localhost:5000"
)

Set-Location "$PSScriptRoot\mobile"

if ($Device) {
    flutter run -d $Device --dart-define="API_BASE_URL=$ApiBaseUrl"
} else {
    flutter run --dart-define="API_BASE_URL=$ApiBaseUrl"
}
