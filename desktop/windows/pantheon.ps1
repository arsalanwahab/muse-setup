# pantheon.ps1 - Muse route CLI for Windows.
#   pantheon status | on | off | heal | config <url> | setup | doctor [--heal]
param(
    [Parameter(Position = 0)][string]$Command = "status",
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest = @()
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$HomeDir = $env:USERPROFILE
$SettingsPath = Join-Path $HomeDir ".config\muse\settings.json"
$RoutePath = Join-Path $HomeDir ".config\muse-vpn\proxy-url"
$HealPath = Join-Path $HomeDir ".config\muse-vpn\heal.json"
$DefaultHost = "184.197.234.208:8443"

function Read-Json([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    try { return Get-Content $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Write-Settings($Settings) {
    New-Item -ItemType Directory -Force -Path (Split-Path $SettingsPath) | Out-Null
    $Settings | ConvertTo-Json -Depth 20 | Set-Content -Path $SettingsPath -Encoding UTF8
}

function Get-Route {
    if (-not (Test-Path $RoutePath)) { return $null }
    $value = (Get-Content $RoutePath -Raw).Trim()
    if ($value.Length -eq 0) { return $null }
    return $value
}

function Save-Route([string]$Value) {
    New-Item -ItemType Directory -Force -Path (Split-Path $RoutePath) | Out-Null
    Set-Content -Path $RoutePath -Value $Value -Encoding ASCII
}

function Get-ActiveProxy {
    $settings = Read-Json $SettingsPath
    if ($null -eq $settings) { return $null }
    if ($settings.PSObject.Properties.Name -contains "endpoint_transport") {
        return $settings.endpoint_transport.proxy
    }
    return $null
}

function Set-ActiveProxy([string]$Value) {
    $settings = Read-Json $SettingsPath
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
    Write-Settings $settings
}

function Hide-Route([string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) { return "-" }
    return ($Value -split "@")[-1] -replace "^.*://", ""
}

function Get-HealConfig {
    $data = Read-Json $HealPath
    if ($null -eq $data -or -not $data.url -or -not $data.token) { return $null }
    return $data
}

function Invoke-Heal {
    $cfg = Get-HealConfig
    if ($null -eq $cfg) {
        Write-Error "no repair config at $HealPath"
        return 1
    }
    try {
        $reply = Invoke-RestMethod -Uri $cfg.url -Method Post -ContentType "application/json" `
            -Body (@{ token = $cfg.token } | ConvertTo-Json)
    } catch {
        Write-Error "repair failed: $($_.Exception.Message)"
        return 1
    }
    if (-not $reply.cidr) {
        Write-Error "repair failed: $($reply | ConvertTo-Json -Compress)"
        return 1
    }
    Write-Host "repaired for $($reply.cidr)"
    return 0
}

function Test-Route {
    $route = Get-ActiveProxy
    if (-not $route) { $route = Get-Route }
    if (-not $route) { return @($false, "no route configured") }
    $result = & curl.exe -sS -m 25 -x $route -o NUL -w "%{http_code} %{time_total}" https://api.meta.ai/v1/models 2>&1
    if ($LASTEXITCODE -ne 0) { return @($false, "route FAILED ($result)") }
    $parts = "$result".Trim().Split(" ")
    $code = $parts[0]
    $elapsed = if ($parts.Count -gt 1) { $parts[1] } else { "?" }
    $ok = @("200", "401", "403") -contains $code
    $note = if (@("401", "403") -contains $code) { " (credential missing or rejected)" } else { "" }
    return @($ok, "route $(if ($ok) {'OK'} else {'FAILED'}) (HTTP $code, ${elapsed}s)$note")
}

function Invoke-Setup {
    $user = (Read-Host "Proxy username").Trim()
    $securePass = Read-Host "Proxy password" -AsSecureString
    $pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))
    $secureKey = Read-Host "Meta API key" -AsSecureString
    $key = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey))
    if (-not $user -or -not $pass -or -not $key) {
        Write-Error "all three values are required"
        return 1
    }

    if (-not (Get-Command muse -ErrorAction SilentlyContinue)) {
        Write-Host "installing muse..."
        Invoke-Expression (Invoke-RestMethod "https://dev.meta.ai/install.ps1")
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [Environment]::GetEnvironmentVariable("Path", "User")
    }

    $host_ = Get-Route
    if (-not $host_) { $host_ = "http://$DefaultHost" }
    if ($host_ -match "://([^@]+@)?(.+)$") { $endpoint = $Matches[2] } else { $endpoint = $DefaultHost }
    $url = "http://" + [uri]::EscapeDataString($user) + ":" + [uri]::EscapeDataString($pass) + "@" + $endpoint

    Set-ActiveProxy $url
    Save-Route $url
    $key | & muse auth set --provider meta --api-key-stdin
    if ($LASTEXITCODE -ne 0) { Write-Error "could not store the API key"; return 1 }
    Write-Host "verifying..."
    $check = & muse exec "reply with exactly: setup-ok" 2>&1 | Out-String
    if ($check -notmatch "setup-ok") {
        Write-Error ("verification failed:`n" + $check.Trim())
        return 1
    }
    Write-Host "ready - run: muse"
    return 0
}

switch ($Command.ToLower()) {
    "status" {
        $on = $null -ne (Get-ActiveProxy)
        Write-Output ("route      : " + $(if ($on) { "ON  -> " + (Hide-Route (Get-ActiveProxy)) } else { "OFF (direct)" }))
        Write-Output ("saved      : " + (Hide-Route (Get-Route)))
        Write-Output ("repair     : " + $(if (Get-HealConfig) { "configured" } else { "not configured" }))
        Write-Output ("muse       : " + $(if (Get-Command muse -ErrorAction SilentlyContinue) { "installed" } else { "missing" }))
    }
    "on" {
        $route = Get-Route
        if (-not $route) { Write-Error "no route saved; run: pantheon config <url>"; exit 1 }
        Set-ActiveProxy $route
        Write-Output ("route ON -> " + (Hide-Route $route))
    }
    "off" {
        Set-ActiveProxy ""
        Write-Output "route OFF (direct)"
    }
    "heal" { exit (Invoke-Heal) }
    "config" {
        if ($Rest.Count -lt 1) { Write-Error "usage: pantheon config <https-url>"; exit 1 }
        $url = $Rest[0]
        if (-not $url.StartsWith("https://")) { Write-Error "config URL must be https"; exit 1 }
        try { $data = Invoke-RestMethod -Uri $url } catch { Write-Error "download failed: $($_.Exception.Message)"; exit 1 }
        if (-not $data.route) { Write-Error 'config must contain {"route": "http://user:pass@host:port"}'; exit 1 }
        Save-Route $data.route
        if ($null -ne (Get-ActiveProxy)) { Set-ActiveProxy $data.route }
        Write-Output ("route updated -> " + (Hide-Route $data.route))
    }
    "setup" { exit (Invoke-Setup) }
    "doctor" {
        $wantHeal = $Rest -contains "--heal"
        $ok, $message = Test-Route
        Write-Output $message
        if ($ok) { exit 0 }
        if (-not $wantHeal) { exit 1 }
        Write-Output "trying repair..."
        if ((Invoke-Heal) -ne 0) { exit 1 }
        $ok, $message = Test-Route
        Write-Output $message
        exit $(if ($ok) { 0 } else { 1 })
    }
    default { Get-Help $PSCommandPath -Detailed }
}
