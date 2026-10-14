@echo off
rem Downloads the latest tagged Mihomo module via the Go proxy and copies it to core\mihomo.
setlocal
call "%~dp0goenv.cmd"
set "ROOT=%~dp0.."
go mod download -json github.com/metacubex/mihomo@latest > "%TEMP%\mihomo-dl.json" || exit /b 1
for /f "usebackq delims=" %%D in (`node -p "require(process.env.TEMP+'/mihomo-dl.json').Dir"`) do set "SRC=%%D"
for /f "usebackq delims=" %%V in (`node -p "require(process.env.TEMP+'/mihomo-dl.json').Version"`) do set "VER=%%V"
echo mihomo %VER% at %SRC%
if exist "%ROOT%\core\mihomo" rmdir /s /q "%ROOT%\core\mihomo"
xcopy /e /i /q /y "%SRC%" "%ROOT%\core\mihomo" >nul || exit /b 1
rem Module cache files are read-only; make the copy writable.
attrib -r "%ROOT%\core\mihomo\*" /s >nul
echo %VER%> "%ROOT%\core\MIHOMO_VERSION"
echo copied to core\mihomo
