@echo off
setlocal
cd /d "%~dp0backend"
set "DOTNET_ROOT_X64=C:\Program Files\dotnet"
set "DOTNET_ROOT=C:\Program Files\dotnet"
if exist "C:\Program Files\dotnet\dotnet.exe" (
    "C:\Program Files\dotnet\dotnet.exe" run --project src\StudyApp.Api
) else (
    dotnet run --project src\StudyApp.Api
)
pause
