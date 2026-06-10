@echo off
set LOG=%~dp0_cleanup_hang.log
echo [%date% %time%] cleanup start>"%LOG%"

taskkill /F /IM git.exe >>"%LOG%" 2>&1
taskkill /F /IM git-remote-https.exe >>"%LOG%" 2>&1
taskkill /F /IM git-credential-manager.exe >>"%LOG%" 2>&1
taskkill /F /IM git-credential-manager-core.exe >>"%LOG%" 2>&1

del /f /q "%~dp0.git\index.lock" >>"%LOG%" 2>&1
if exist "%~dp0.git\index.lock" (
  echo index.lock still present>>"%LOG%"
) else (
  echo index.lock removed or absent>>"%LOG%"
)

echo [%date% %time%] cleanup done>>"%LOG%"
