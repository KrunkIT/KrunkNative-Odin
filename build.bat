@echo off
rem Build helper for Windows (requires Odin compiler in PATH).
rem
rem Usage:
rem   build.bat client            build the client      -> bin\krunknative_client.exe
rem   build.bat server            build the server      -> bin\krunknative_server.exe
rem   build.bat tests             build + run the sim tests
rem   build.bat check             typecheck client + server without linking
rem   build.bat all               build client + server
rem   build.bat clean             remove built binaries
rem   build.bat (no args)         same as "all"

setlocal
set "BIN_DIR=bin"
set "ODIN=odin"
set "TARGET=%~1"

if "%TARGET%"=="" set "TARGET=all"

where %ODIN% >nul 2>nul
if errorlevel 1 (
    echo Error: Odin compiler not found in PATH. Install it from https://odin-lang.org
    exit /b 1
)

if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"

goto:%TARGET%

:client
%ODIN% build src/client -out:%BIN_DIR%\krunknative_client.exe -o:aggressive
exit /b %errorlevel%

:server
%ODIN% build src/server -out:%BIN_DIR%\krunknative_server.exe -o:aggressive
exit /b %errorlevel%

:tests
%ODIN% build src/tests -out:%BIN_DIR%\krunknative_tests.exe -o:aggressive
if errorlevel 1 exit /b %errorlevel%
"%BIN_DIR%\krunknative_tests.exe"
exit /b %errorlevel%

:check
%ODIN% check src/client
if errorlevel 1 exit /b %errorlevel%
%ODIN% check src/server
exit /b %errorlevel%

:all
call :client
if errorlevel 1 exit /b %errorlevel%
call :server
exit /b %errorlevel%

:clean
if exist "%BIN_DIR%\krunknative_client.exe" del "%BIN_DIR%\krunknative_client.exe"
if exist "%BIN_DIR%\krunknative_server.exe" del "%BIN_DIR%\krunknative_server.exe"
if exist "%BIN_DIR%\krunknative_tests.exe" del "%BIN_DIR%\krunknative_tests.exe"
echo Cleaned %BIN_DIR%\
exit /b 0

:default
echo Unknown target: %TARGET%
echo.
echo Usage: build.bat [client ^| server ^| tests ^| check ^| all ^| clean]
exit /b 1
