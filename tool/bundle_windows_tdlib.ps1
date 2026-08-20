param(
  [string]$ReleaseDir = "build/windows/x64/runner/Release",
  [string]$PackageVersion = "",
  [string]$PackageUri = "",
  [string]$SecretBase64 = $env:TDJSON_WINDOWS_DLL_BASE64
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($PackageVersion)) {
  if ([string]::IsNullOrWhiteSpace($env:TDLIB_NATIVE_VERSION)) {
    $PackageVersion = "1.8.66"
  } else {
    $PackageVersion = $env:TDLIB_NATIVE_VERSION
  }
}

if (-not (Test-Path $ReleaseDir)) {
  throw "Windows release directory missing: $ReleaseDir"
}

$resolvedReleaseDir = (Resolve-Path $ReleaseDir).Path

function Assert-TdjsonPresent {
  param([string]$DirectoryPath)

  $tdjsonPath = Join-Path $DirectoryPath "tdjson.dll"
  if (-not (Test-Path $tdjsonPath)) {
    throw "tdjson.dll was not bundled into $DirectoryPath"
  }

  $tdjson = Get-Item $tdjsonPath
  if ($tdjson.Length -le 0) {
    throw "Bundled tdjson.dll is empty"
  }
}

if (-not [string]::IsNullOrWhiteSpace($SecretBase64)) {
  $dllPath = Join-Path $resolvedReleaseDir "tdjson.dll"
  [IO.File]::WriteAllBytes($dllPath, [Convert]::FromBase64String($SecretBase64))
  Assert-TdjsonPresent -DirectoryPath $resolvedReleaseDir
  Write-Host "Bundled tdjson.dll from TDJSON_WINDOWS_DLL_BASE64."
  exit 0
}

if ([string]::IsNullOrWhiteSpace($PackageUri)) {
  $PackageUri = "https://www.nuget.org/api/v2/package/tdlib.native.win-x64/$PackageVersion"
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("teleplayer-tdlib-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
  $packagePath = Join-Path $tempRoot "tdlib.native.win-x64.$PackageVersion.zip"
  $extractDir = Join-Path $tempRoot "package"

  $delaySeconds = 5
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      Write-Host "Downloading tdlib.native.win-x64 $PackageVersion from NuGet (attempt $attempt of 3)."
      Invoke-WebRequest -Uri $PackageUri -OutFile $packagePath -UseBasicParsing
      break
    } catch {
      if ($attempt -eq 3) {
        throw
      }
      Write-Warning "TDLib runtime download failed; retrying in $delaySeconds seconds."
      Start-Sleep -Seconds $delaySeconds
      $delaySeconds *= 2
    }
  }

  if (-not (Test-Path $packagePath)) {
    throw "TDLib runtime package was not downloaded"
  }

  $package = Get-Item $packagePath
  if ($package.Length -le 0) {
    throw "TDLib runtime package is empty"
  }

  Expand-Archive -Path $packagePath -DestinationPath $extractDir -Force

  $candidateDirs = @(
    (Join-Path $extractDir "runtimes/win-x64/native"),
    (Join-Path $extractDir "runtimes/win-x64")
  )
  $nativeDir = $candidateDirs |
    Where-Object { Test-Path (Join-Path $_ "tdjson.dll") } |
    Select-Object -First 1

  if (-not $nativeDir) {
    $tdjson = Get-ChildItem -Path $extractDir -Recurse -Filter "tdjson.dll" -File |
      Select-Object -First 1
    if (-not $tdjson) {
      throw "tdjson.dll was not found in the tdlib.native.win-x64 package"
    }
    $nativeDir = $tdjson.Directory.FullName
  }

  $dlls = Get-ChildItem -Path $nativeDir -Filter "*.dll" -File
  if (-not $dlls) {
    throw "No DLL files were found in the TDLib runtime directory: $nativeDir"
  }

  foreach ($dll in $dlls) {
    Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $resolvedReleaseDir $dll.Name) -Force
    Write-Host "Bundled $($dll.Name) ($([math]::Round($dll.Length / 1MB, 2)) MB)."
  }

  Assert-TdjsonPresent -DirectoryPath $resolvedReleaseDir
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
