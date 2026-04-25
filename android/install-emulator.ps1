param(
    [string]$Name = "LunaPixel",
    [string]$Package = "system-images;android-36;google_apis;x86_64",
    [string]$Device = "pixel_6"
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

$sdkRoot = Find-AndroidSdk
$sdkManager = Join-Path $sdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"
$avdManager = Join-Path $sdkRoot "cmdline-tools\latest\bin\avdmanager.bat"
$emulator = Join-Path $sdkRoot "emulator\emulator.exe"

if (-not (Test-Path -LiteralPath $sdkManager)) {
    throw "sdkmanager was not found at $sdkManager. Install Android SDK Command-line Tools in Android Studio."
}

Write-Host "Installing emulator packages. This can take a while..."
& $sdkManager "platform-tools" "emulator" "platforms;android-36" $Package
if ($LASTEXITCODE -ne 0) {
    throw "sdkmanager failed."
}

if (-not (Test-Path -LiteralPath $avdManager)) {
    throw "avdmanager was not found at $avdManager after installation."
}

$existing = if (Test-Path -LiteralPath $emulator) { & $emulator -list-avds } else { @() }
if ($existing -contains $Name) {
    Write-Host "AVD '$Name' already exists."
} else {
    Write-Host "Creating AVD '$Name'..."
    "no" | & $avdManager create avd -n $Name -k $Package -d $Device --force
    if ($LASTEXITCODE -ne 0) {
        throw "avdmanager failed."
    }
}

Write-Host "Emulator setup complete."
Write-Host "Run: .\run-android.ps1 -AvdName $Name"
