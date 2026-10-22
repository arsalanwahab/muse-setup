# Pantheon Setup for Windows — GUI installer.
# Installs the Muse CLI, stores the user's own API key, points it at the
# company egress proxy, and verifies the connection.

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ProxyHost = "184.197.234.208:8443"
$Title = "Pantheon Setup"

function Show-Input {
    param([string]$Prompt, [switch]$Secret)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(460, 170)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Prompt
    $label.Location = New-Object System.Drawing.Point(15, 15)
    $label.Size = New-Object System.Drawing.Size(420, 20)

    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point(15, 40)
    $box.Size = New-Object System.Drawing.Size(415, 25)
    if ($Secret) { $box.UseSystemPasswordChar = $true }

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "Continue"
    $ok.DialogResult = "OK"
    $ok.Location = New-Object System.Drawing.Point(255, 80)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.DialogResult = "Cancel"
    $cancel.Location = New-Object System.Drawing.Point(345, 80)

    $form.Controls.AddRange(@($label, $box, $ok, $cancel))
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel

    if ($form.ShowDialog() -eq "OK" -and $box.Text.Trim().Length -gt 0) {
        return $box.Text.Trim()
    }
    return $null
}

function Show-Message {
    param([string]$Text, [switch]$IsError)
    $icon = if ($IsError) { "Error" } else { "Information" }
    [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, "OK", $icon)
}

try {
    if (-not ($env:MUSE_PROXY_USER -and $env:MUSE_PROXY_PASS -and $env:META_API_KEY)) {
        Show-Message "This sets up the Muse agent on your PC.`n`nYou need:`n  - the proxy username and password from your admin`n  - your own Meta API key (dev.meta.ai -> API Keys)"
        $env:MUSE_PROXY_USER = Show-Input "Proxy username:"
        if (-not $env:MUSE_PROXY_USER) { exit 0 }
        $env:MUSE_PROXY_PASS = Show-Input "Proxy password:" -Secret
        if (-not $env:MUSE_PROXY_PASS) { exit 0 }
        $env:META_API_KEY = Show-Input "Your Meta API key (input hidden):" -Secret
        if (-not $env:META_API_KEY) { exit 0 }
    }

    $proxy = "http://" + [uri]::EscapeDataString($env:MUSE_PROXY_USER) + ":" +
             [uri]::EscapeDataString($env:MUSE_PROXY_PASS) + "@$ProxyHost"

    if (-not (Get-Command muse -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Muse CLI..."
        Invoke-Expression (Invoke-RestMethod "https://dev.meta.ai/install.ps1")
        $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $env:Path = "$machinePath;$userPath"
    }

    $configDir = Join-Path $env:USERPROFILE ".config\muse"
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    $settingsPath = Join-Path $configDir "settings.json"

    $settings = $null
    if (Test-Path $settingsPath) {
        try { $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json } catch { $settings = $null }
    }
    if ($null -eq $settings) { $settings = [pscustomobject]@{} }
    if (-not ($settings.PSObject.Properties.Name -contains "schema_version")) {
        $settings | Add-Member -NotePropertyName schema_version -NotePropertyValue 1 -Force
    }
    if (-not ($settings.PSObject.Properties.Name -contains "endpoint_transport")) {
        $settings | Add-Member -NotePropertyName endpoint_transport -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $settings.endpoint_transport | Add-Member -NotePropertyName proxy -NotePropertyValue $proxy -Force
    $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding UTF8
    Write-Host "Proxy configured."

    $env:META_API_KEY | & muse auth set --provider meta --api-key-stdin
    if ($LASTEXITCODE -ne 0) { throw "could not store the API key" }
    Write-Host "Key stored."

    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $out = & muse exec "reply with exactly: setup-ok" 2>&1 | Out-String
    $ErrorActionPreference = $previous
    if ($out -match "setup-ok") {
        Show-Message "Pantheon + Muse is ready.`n`nOpen a terminal, cd into a project, and run:`n`n    muse"
    } else {
        $tail = $out.Substring([Math]::Max(0, $out.Length - 700))
        Show-Message "Setup failed:`n`n$tail" -IsError
        exit 1
    }
}
catch {
    Show-Message "Setup failed:`n`n$($_.Exception.Message)" -IsError
    exit 1
}
