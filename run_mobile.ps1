# Run the Flutter mobile app from the repository root
param(
    [string]$Device = ""
)

Set-Location "$PSScriptRoot\mobile"

if ($Device) {
    flutter run -d $Device
} else {
    flutter run
}
