@echo off
setlocal
cd /d "%~dp0"
if not exist ".env" (
    echo Chua co .env. Mo README.md de ket noi PostgreSQL.
    pause
    exit /b 1
)
if not exist ".venv\Scripts\python.exe" (
    echo Chua cai Python cho demo. Mo README.md de cai thu vien.
    pause
    exit /b 1
)
echo Mini-Upwork Phase 4 - http://127.0.0.1:8014
echo Mo dia chi tren bang trinh duyet. Nhan Ctrl+C de dung.
".venv\Scripts\python.exe" -m uvicorn miniupwork.phase4:app --host 127.0.0.1 --port 8014
if errorlevel 1 pause
