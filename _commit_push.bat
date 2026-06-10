@echo off
cd /d "%~dp0"
echo [%date% %time%] start>>_git_push.log
taskkill /F /IM git.exe 2>nul
del /f /q .git\index.lock 2>nul
set GIT_OPTIONAL_LOCKS=0
set GIT=git -c core.fsmonitor=false

%GIT% add CHANGELOG_kesh.txt modules\charm.lua modules\mez.lua modules\class.lua modules\move.lua init.lua class_configs\Live-kesh\pal_class_config.lua class_configs\Live-kesh\dru_class_config.lua class_configs\Live-kesh\enc_class_config.lua utils\casting.lua utils\combat.lua utils\globals.lua utils\modules.lua utils\targeting.lua>>_git_push.log 2>&1
if errorlevel 1 (echo ADD_FAILED>>_git_push.log & exit /b 1)

%GIT% commit -m "CC priority and PAL updates">>_git_push.log 2>&1
if errorlevel 1 (echo COMMIT_FAILED>>_git_push.log & exit /b 1)

%GIT% push origin kesh-custom>>_git_push.log 2>&1
echo [%date% %time%] done exit=%errorlevel%>>_git_push.log
exit /b %errorlevel%
