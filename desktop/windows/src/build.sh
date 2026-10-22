#!/bin/sh
# Cross-build both Windows .exe files (needs Go 1.21+). Run from anywhere.
set -e
cd "$(dirname "$0")"
cp ../PantheonSetup.ps1 setup/script.ps1
cp ../PantheonTray.ps1 tray/script.ps1
(cd setup && GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "-H=windowsgui -s -w" -o ../../PantheonSetup.exe .)
(cd tray  && GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "-H=windowsgui -s -w" -o ../../PantheonTray.exe .)
echo "built PantheonSetup.exe and PantheonTray.exe"
