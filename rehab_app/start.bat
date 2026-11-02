@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
title Реабілітаційний центр - демонстраційний вебінтерфейс

rem ---- 0. Файл має лежати в папці rehab_app поруч з app.py ----
if not exist "app.py" (
    echo [ПОМИЛКА] Поруч із start.bat немає app.py.
    echo Запускайте start.bat з розпакованої папки rehab_center\rehab_app,
    echo а не окремо, наприклад з робочого столу.
    pause
    exit /b 1
)

rem ---- 1. Пошук Python ----
set "PY="
py -3 --version >nul 2>nul && set "PY=py -3"
if not defined PY (
    python --version >nul 2>nul && set "PY=python"
)
if not defined PY (
    echo [ПОМИЛКА] Python не знайдено.
    echo Встановіть Python 3.10+ з https://www.python.org/downloads/
    echo і на першому екрані інсталятора поставте галочку "Add python.exe to PATH".
    pause
    exit /b 1
)

rem ---- 2. Залежності (встановлюються лише перший раз) ----
%PY% -c "import flask, mysql.connector" >nul 2>nul
if errorlevel 1 (
    echo Встановлюю залежності з requirements.txt ...
    %PY% -m pip install -r requirements.txt
    if errorlevel 1 (
        echo [ПОМИЛКА] Не вдалося встановити залежності - див. повідомлення pip вище.
        pause
        exit /b 1
    )
)

rem ---- 3. Вибір робочого місця (облікового запису MySQL) ----
echo.
echo   1 - Реєстратура  (rehab_app, роль адміністратора, без записів прогресу)
echo   2 - Керівник     (director, бачить записи прогресу)
echo.
set "MODE=%~1"
if not defined MODE (
    choice /c 12 /n /m "Оберіть робоче місце [1/2]: "
    if errorlevel 2 (set "MODE=2") else (set "MODE=1")
)
if "%MODE%"=="2" (
    set "DB_USER=director"
    set "DB_PASSWORD=Dir#2026pass"
) else (
    set "DB_USER=rehab_app"
    set "DB_PASSWORD=App#2026pass"
)
if not defined DB_HOST set "DB_HOST=localhost"

rem ---- 4. Запуск ----
echo.
echo Користувач БД: %DB_USER%. Застосунок: http://127.0.0.1:5000
echo Щоб зупинити, натисніть Ctrl+C або закрийте це вікно.
echo.
start "" cmd /c "timeout /t 3 /nobreak >nul & start "" http://127.0.0.1:5000"
%PY% app.py
echo.
echo Застосунок зупинено. Якщо вище є помилка підключення - перевірте, що служба MySQL96 запущена
echo і що виконано скрипти 01_schema.sql та 02_data.sql.
pause
