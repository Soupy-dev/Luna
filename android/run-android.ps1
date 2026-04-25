param(
    [string]$AvdName,
    [string]$GpuMode = "host",
    [switch]$NoBuild,
    [switch]$Release,
    [switch]$SkipLaunch,
    [switch]$KeepDeviceAnimations,
    [int]$BootTimeoutSeconds = 180
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

    throw "Android SDK was not found. Install Android Studio or set ANDROID_HOME."
}

function Get-ConnectedDeviceCount {
    $lines = & $adb devices | Select-Object -Skip 1
    return @($lines | Where-Object { $_ -match "\sdevice$" }).Count
}

function Wait-ForBoot {
    param([int]$TimeoutSeconds)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    & $adb wait-for-device

    while ((Get-Date) -lt $deadline) {
        $booted = (& $adb shell getprop sys.boot_completed 2>$null | Select-Object -First 1).Trim()
        if ($booted -eq "1") {
            return
        }
        Start-Sleep -Seconds 3
    }

    throw "Timed out waiting for Android device to boot."
}

function Optimize-DeviceForTesting {
    if ($KeepDeviceAnimations) {
        return
    }

    Write-Host "Disabling device animations for smoother testing..."
    & $adb shell settings put global window_animation_scale 0 | Out-Null
    & $adb shell settings put global transition_animation_scale 0 | Out-Null
    & $adb shell settings put global animator_duration_scale 0 | Out-Null
}

$sdkRoot = Find-AndroidSdk
$adb = Join-Path $sdkRoot "platform-tools\adb.exe"
$emulator = Join-Path $sdkRoot "emulator\emulator.exe"
$gradle = Join-Path $PSScriptRoot "gradlew.bat"
$variant = if ($Release) { "release" } else { "debug" }
$assembleTask = if ($Release) { ":app:assembleRelease" } else { ":app:assembleDebug" }
$apkPath = if ($Release) {
    Join-Path $PSScriptRoot "app\build\outputs\apk\release\app-release.apk"
} else {
    Join-Path $PSScriptRoot "app\build\outputs\apk\debug\app-debug.apk"
}

if (-not (Test-Path -LiteralPath $adb)) {
    throw "adb was not found at $adb. Install Android SDK platform-tools."
}
if (-not (Test-Path -LiteralPath $gradle)) {
    throw "Gradle wrapper was not found at $gradle."
}

Push-Location $PSScriptRoot
try {
    if (-not $NoBuild) {
        Write-Host "Building Android $variant APK..."
        & $gradle $assembleTask
        if ($LASTEXITCODE -ne 0) {
            throw "Gradle build failed."
        }
    }

    if (-not (Test-Path -LiteralPath $apkPath)) {
        throw "APK was not found at $apkPath. Build it first or omit -NoBuild."
    }

    if ((Get-ConnectedDeviceCount) -eq 0) {
        if (-not $AvdName) {
            throw "No Android device is connected. Connect a USB device or pass -AvdName after creating an emulator with .\install-emulator.ps1."
        }
        if (-not (Test-Path -LiteralPath $emulator)) {
            throw "Android Emulator is not installed. Run .\install-emulator.ps1 first."
        }

        Write-Host "Starting emulator '$AvdName' with GPU mode '$GpuMode'..."
        Start-Process -FilePath $emulator -ArgumentList @(
            "-avd",
            $AvdName,
            "-gpu",
            $GpuMode,
            "-no-boot-anim",
            "-no-snapshot-load"
        )
        Wait-ForBoot -TimeoutSeconds $BootTimeoutSeconds
    }

    Optimize-DeviceForTesting

    Write-Host "Installing $apkPath..."
    & $adb install -r $apkPath
    if ($LASTEXITCODE -ne 0) {
        throw "APK install failed."
    }

    if (-not $SkipLaunch) {
        Write-Host "Launching Luna Android..."
        & $adb shell monkey -p dev.soupy.eclipse.android -c android.intent.category.LAUNCHER 1 | Out-Host
    }

    Write-Host "Done."
} finally {
    Pop-Location
}
