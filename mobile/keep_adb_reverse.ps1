$adbPath = "C:\Users\User\AppData\Local\Android\Sdk\platform-tools\adb.exe"
Write-Host "Starting ADB Reverse Daemon for port 5000..."

while ($true) {
    try {
        & $adbPath reverse tcp:5000 tcp:5000 2>$null
    } catch {
        # ignore transient USB state changes
    }
    Start-Sleep -Seconds 2
}
