@echo off
chcp 65001 >nul
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo 未检测到 Node.js。您可以直接双击 index.html 查看，或安装 Node.js 后重新运行此脚本。
  pause
  exit /b 1
)
start "" http://127.0.0.1:5188
node server.js
pause
