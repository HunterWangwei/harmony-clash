@echo off
rem Shared Go environment for building the Mihomo core (called by other scripts).
set "GOROOT=%USERPROFILE%\.local\go"
set "PATH=%GOROOT%\bin;%PATH%"
set "GOPATH=%USERPROFILE%\.local\gopath"
set "GOPROXY=https://goproxy.cn,https://proxy.golang.org,direct"
set "GOSUMDB=sum.golang.google.cn"
