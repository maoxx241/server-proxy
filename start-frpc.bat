@echo off
chcp 65001 >nul
title FRP Client

echo ========================================
echo FRP Client
echo ========================================
echo.

if not exist "frp\frpc.exe" (
    echo [ERROR] frpc.exe not found
    echo Please download frp from:
    echo https://github.com/fatedier/frp/releases
    pause
    exit /b 1
)

if not exist "frpc.toml" (
    echo [ERROR] frpc.toml not found
    pause
    exit /b 1
)

echo [INFO] Starting frp client...
echo [INFO] Config: frpc.toml
echo [INFO] Press Ctrl+C to stop
echo.

cd /d "%~dp0"
frp\frpc.exe -c frpc.toml

if errorlevel 1 (
    echo.
    echo [ERROR] frpc failed to start
    echo Check config and server connection
    pause
)
