@echo off
chcp 65001 >nul
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo 请先安装 Node.js 22.14 或更新版本。
  pause
  exit /b 1
)
echo 打开 http://127.0.0.1:19091 使用模拟器，按 Ctrl+C 停止。
node server.mjs
if errorlevel 1 pause
