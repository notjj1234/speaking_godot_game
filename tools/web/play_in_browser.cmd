@echo off
rem Windows launcher for play_in_browser.py — export the Web build and play it at http://localhost:8060.
rem   tools\web\play_in_browser.cmd               export, serve, open the browser
rem   tools\web\play_in_browser.cmd --no-export   serve the last export
rem   tools\web\play_in_browser.cmd --export-only
rem Set GODOT to override the editor, e.g. set GODOT=C:\Godot\Godot_v4.7.1-stable_win64_console.exe
setlocal
set "SCRIPT=%~dp0play_in_browser.py"
where py >nul 2>nul && (py -3 "%SCRIPT%" %* & goto :done)
where python >nul 2>nul && (python "%SCRIPT%" %* & goto :done)
echo [X] Python 3 not found. Install it from https://www.python.org/downloads/ and tick "Add to PATH".
:done
set "RC=%ERRORLEVEL%"
rem Keep the window open when double-clicked from Explorer.
echo %CMDCMDLINE% | find /i "/c" >nul && pause
exit /b %RC%
