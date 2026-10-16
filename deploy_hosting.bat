@echo off
setlocal
cd /d "%~dp0"
echo ========================================================
echo   StudyApp - Firebase Hosting Build & Deploy
echo ========================================================
echo.

set "API_URL=%~1"
if "%API_URL%"=="" set "API_URL=https://study-app-b0xq.onrender.com"

echo Target API: %API_URL%
echo Target Project: studyapp-51772
echo.

echo [1/3] Checking Firebase authentication...
call firebase login:list >nul 2>&1
if errorlevel 1 (
    echo.
    echo [!] You are not currently logged in to Firebase.
    echo Opening browser for Firebase authentication...
    call firebase login
    if errorlevel 1 (
        echo [ERROR] Firebase login failed.
        pause
        exit /b 1
    )
)

echo [OK] Firebase is authenticated.
echo.

echo [2/3] Building Flutter Web (Release)...
cd mobile
call flutter build web --release --dart-define=API_BASE_URL=%API_URL%
if errorlevel 1 (
    echo [ERROR] Flutter web compilation failed.
    cd ..
    pause
    exit /b 1
)
cd ..
echo [OK] Web build ready in mobile/build/web.
echo.

echo [3/3] Deploying to Firebase Hosting (studyapp-51772)...
call firebase deploy --only hosting --project studyapp-51772
if errorlevel 1 (
    echo [ERROR] Firebase deployment failed.
    pause
    exit /b 1
)

echo.
echo ========================================================
echo   Deployment Complete!
echo   Live URL: https://studyapp-51772.web.app
echo ========================================================
pause
