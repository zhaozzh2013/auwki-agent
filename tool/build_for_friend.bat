@echo off
chcp 65001 >nul
echo ============================================
echo  AUWKI Agent - one-click helper build
echo ============================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_for_friend.ps1" %*
if errorlevel 1 (
  echo.
  echo [FAILED] Build did not complete. Read the messages above.
)
echo.
pause
