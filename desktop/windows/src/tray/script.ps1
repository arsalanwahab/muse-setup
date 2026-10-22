Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Title = "Pantheon Egress"
$settingsPath = Join-Path $env:USERPROFILE ".config\muse\settings.json"
$routeFile = Join-Path $env:USERPROFILE ".config\muse-vpn\proxy-url"

function Get-ProxyUrl {
    if (-not (Test-Path $routeFile)) { return $null }
    $value = (Get-Content $routeFile -Raw).Trim()
    if ($value.Length -eq 0) { return $null }
    return $value
}

function Get-CurrentProxy {
    if (-not (Test-Path $settingsPath)) { return $null }
    try {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
        if ($settings.PSObject.Properties.Name -contains "endpoint_transport") {
            return $settings.endpoint_transport.proxy
        }
    } catch { }
    return $null
}

function Set-CurrentProxy {
    param([string]$Value)
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
    if ([string]::IsNullOrEmpty($Value)) {
        $settings.endpoint_transport.PSObject.Properties.Remove("proxy")
    } else {
        $settings.endpoint_transport | Add-Member -NotePropertyName proxy -NotePropertyValue $Value -Force
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $settingsPath) | Out-Null
    $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding UTF8
}

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Application
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$toggleItem = New-Object System.Windows.Forms.ToolStripMenuItem
$quitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$quitItem.Text = "Quit"
$quitItem.add_Click({ $notify.Visible = $false; [System.Windows.Forms.Application]::Exit() })
[void]$menu.Items.Add($toggleItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($quitItem)
$notify.ContextMenuStrip = $menu

function Update-State {
    $on = $null -ne (Get-CurrentProxy)
    $toggleItem.Text = if ($on) { "Turn US egress off" } else { "Turn US egress on" }
    $notify.Text = if ($on) { "$Title - Pantheon Routes: ON" } else { "$Title - Pantheon Routes: OFF" }
}

$toggleItem.add_Click({
    if ($null -ne (Get-CurrentProxy)) {
        Set-CurrentProxy ""
        $notify.ShowBalloonTip(1500, $Title, "Pantheon Routes: OFF (direct)", "Info")
    } else {
        $route = Get-ProxyUrl
        if ($null -eq $route) {
            $notify.ShowBalloonTip(3000, $Title, "No route configured. Run Pantheon Setup first.", "Warning")
        } else {
            Set-CurrentProxy $route
            $notify.ShowBalloonTip(1500, $Title, "Pantheon Routes: ON", "Info")
        }
    }
    Update-State
})

Update-State
[System.Windows.Forms.Application]::Run()
