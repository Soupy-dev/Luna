param(
    [switch]$VerboseOutput
)

$ErrorActionPreference = "Stop"

function Find-AndroidSdk {
    if ($env:ANDROID_HOME -and (Test-Path -LiteralPath $env:ANDROID_HOME)) {
        return (Resolve-Path -LiteralPath $env:ANDROID_HOME).Path
    }
    if ($env:ANDROID_SDK_ROOT -and (Test-Path -LiteralPath $env:ANDROID_SDK_ROOT)) {
        return (Resolve-Path -LiteralPath $env:ANDROID_SDK_ROOT).Path
    }

    $defaultSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
    if (Test-Path -LiteralPath $defaultSdk) {
        return (Resolve-Path -LiteralPath $defaultSdk).Path
    }

    return $null
}

function Test-Tool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Write-Host "[ok] $Label`: $Path"
        return $true
    }

    Write-Host "[missing] $Label`: $Path"
    return $false
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$gradleWrapper = Join-Path $PSScriptRoot "gradlew.bat"
$sdkRoot = Find-AndroidSdk

Write-Host "Android project: $PSScriptRoot"
Write-Host "Repository: $repoRoot"

$ok = $true
$ok = (Test-Tool -Label "Gradle wrapper" -Path $gradleWrapper) -and $ok

if (-not $sdkRoot) {
    Write-Host "[missing] Android SDK. Install Android Studio or set ANDROID_HOME."
    $ok = $false
} else {
    Write-Host "[ok] Android SDK: $sdkRoot"
    $adb = Join-Path $sdkRoot "platform-tools\adb.exe"
    $sdkManager = Join-Path $sdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"
    $emulator = Join-Path $sdkRoot "emulator\emulator.exe"
    $avdManager = Join-Path $sdkRoot "cmdline-tools\latest\bin\avdmanager.bat"

    $ok = (Test-Tool -Label "adb" -Path $adb) -and $ok
    $ok = (Test-Tool -Label "sdkmanager" -Path $sdkManager) -and $ok
    [void](Test-Tool -Label "emulator" -Path $emulator)
    [void](Test-Tool -Label "avdmanager" -Path $avdManager)

    if (Test-Path -LiteralPath $adb) {
        Write-Host ""
        Write-Host "Connected devices:"
        & $adb devices
    }

    if (Test-Path -LiteralPath $emulator) {
        Write-Host ""
        Write-Host "Available emulators:"
        $avds = & $emulator -list-avds
        if ($avds) {
            $avds | ForEach-Object { Write-Host "  $_" }
        } else {
            Write-Host "  none"
        }
    }
}

Write-Host ""
if ($ok) {
    Write-Host "Setup is ready for USB-device builds. Run .\run-android.ps1 from the android folder."
    if ($VerboseOutput) {
        Write-Host "Use .\install-emulator.ps1 to install/create a local emulator."
    }
    exit 0
}

Write-Host "Setup is missing required pieces. See the [missing] lines above."
exit 1
