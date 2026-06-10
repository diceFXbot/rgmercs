@echo off
echo [%date% %time%] stop start>_stop_all.log
taskkill /F /IM git.exe >>_stop_all.log 2>&1
taskkill /F /IM git-remote-https.exe >>_stop_all.log 2>&1
taskkill /F /IM git-credential-manager.exe >>_stop_all.log 2>&1
del /f /q .git\index.lock >>_stop_all.log 2>&1
echo [%date% %time%] stop done>>_stop_all.log
