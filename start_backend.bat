@echo off
cd /d "%~dp0backend"
dotnet run --project src\StudyApp.Api
pause
