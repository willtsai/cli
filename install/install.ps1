# ------------------------------------------------------------
# Copyright (c) Microsoft Corporation and Dapr Contributors.
# Licensed under the MIT License.
# ------------------------------------------------------------
param (
    [string]$Version,
    [string]$DaprRoot = "c:\dapr",
    [string]$DaprReleaseJsonUrl = "",
    [scriptblock]$CustomAssetFactory = $null
)

Write-Output ""
$ErrorActionPreference = 'stop'

#Escape space of DaprRoot path
$DaprRoot = $DaprRoot -replace ' ', '` '

# Constants
$DaprCliFileName = "dapr.exe"
$DaprCliFilePath = "${DaprRoot}\${DaprCliFileName}"

# GitHub Org and repo hosting Dapr CLI
$GitHubOrg = "dapr"
$GitHubRepo = "cli"

# Set Github request authentication for basic authentication.
if ($Env:GITHUB_USER) {
    $basicAuth = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Env:GITHUB_USER + ":" + $Env:GITHUB_TOKEN));
    $githubHeader = @{"Authorization" = "Basic $basicAuth" }
}
else {
    $githubHeader = @{}
}

if ((Get-ExecutionPolicy) -gt 'RemoteSigned' -or (Get-ExecutionPolicy) -eq 'ByPass') {
    Write-Output "PowerShell requires an execution policy of 'RemoteSigned'."
    Write-Output "To make this change please run:"
    Write-Output "'Set-ExecutionPolicy RemoteSigned -scope CurrentUser'"
    break
}

# Change security protocol to support TLS 1.2 / 1.1 / 1.0 - old powershell uses TLS 1.0 as a default protocol
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

# Check if Dapr CLI is installed.
if (Test-Path $DaprCliFilePath -PathType Leaf) {
    Write-Warning "Dapr is detected - $DaprCliFilePath"
    Invoke-Expression "$DaprCliFilePath --version"
    Write-Output "Reinstalling Dapr..."
}
else {
    Write-Output "Installing Dapr..."
}

# Create Dapr Directory
Write-Output "Creating $DaprRoot directory"
New-Item -ErrorAction Ignore -Path $DaprRoot -ItemType "directory"
if (!(Test-Path $DaprRoot -PathType Container)) {
    Write-Warning "Please visit https://docs.dapr.io/getting-started/install-dapr-cli/ for instructions on how to install without admin rights."
    throw "Cannot create $DaprRoot"
}

# Get the list of release from GitHub
$releaseJsonUrl = $DaprReleaseJsonUrl
if (!$releaseJsonUrl) {
    $releaseJsonUrl = "https://api.github.com/repos/${GitHubOrg}/${GitHubRepo}/releases"
}

$releases = Invoke-RestMethod -Headers $githubHeader -Uri $releaseJsonUrl -Method Get
if ($releases.Count -eq 0) {
    throw "No releases from github.com/dapr/cli repo"
}

# get latest or specified version info from releases
function GetVersionInfo {
    param (
        [string]$Version,
        $Releases
    )
    # Filter windows binary and download archive
    if (!$Version) {
        $release = $Releases | Where-Object { $_.tag_name -notlike "*rc*" } | Select-Object -First 1
    }
    else {
        $release = $Releases | Where-Object { $_.tag_name -eq "v$Version" } | Select-Object -First 1
    }

    return $release
}

# get info about windows asset from release
function GetWindowsAsset {
    param (
        $Release
    )
    if ($CustomAssetFactory) {
        Write-Output "CustomAssetFactory dectected, try to invoke it"
        return $CustomAssetFactory.Invoke($Release)
    }
    else {
        $windowsAsset = $Release | Select-Object -ExpandProperty assets | Where-Object { $_.name -Like "*windows_amd64.zip" }
        if (!$windowsAsset) {
            throw "Cannot find the windows Dapr CLI binary"
        }
        [hashtable]$return = @{}
        $return.url = $windowsAsset.url
        $return.name = $windowsAsset.name
        return $return
    }`
}

$release = GetVersionInfo -Version $Version -Releases $releases
if (!$release) {
    throw "Cannot find the specified Dapr CLI binary version"
}
$asset = GetWindowsAsset -Release $release
$zipFileUrl = $asset.url
$assetName = $asset.name

$zipFilePath = $DaprRoot + "\" + $assetName
Write-Output "Downloading $zipFileUrl ..."

$githubHeader.Accept = "application/octet-stream"
Invoke-WebRequest -Headers $githubHeader -Uri $zipFileUrl -OutFile $zipFilePath
if (!(Test-Path $zipFilePath -PathType Leaf)) {
    throw "Failed to download Dapr Cli binary - $zipFilePath"
}

# Extract Dapr CLI to $DaprRoot
Write-Output "Extracting $zipFilePath..."
Microsoft.Powershell.Archive\Expand-Archive -Force -Path $zipFilePath -DestinationPath $DaprRoot
if (!(Test-Path $DaprCliFilePath -PathType Leaf)) {
    throw "Failed to download Dapr Cli archieve - $zipFilePath"
}

# Check the Dapr CLI version
Invoke-Expression "$DaprCliFilePath --version"

# Clean up zipfile
Write-Output "Clean up $zipFilePath..."
Remove-Item $zipFilePath -Force

# Add DaprRoot directory to User Path environment variable
Write-Output "Try to add $DaprRoot to User Path Environment variable..."
$UserPathEnvironmentVar = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($UserPathEnvironmentVar -like '*dapr*') {
    Write-Output "Skipping to add $DaprRoot to User Path - $UserPathEnvironmentVar"
}
else {
    [System.Environment]::SetEnvironmentVariable("PATH", $UserPathEnvironmentVar + ";$DaprRoot", "User")
    $UserPathEnvironmentVar = [Environment]::GetEnvironmentVariable("PATH", "User")
    Write-Output "Added $DaprRoot to User Path - $UserPathEnvironmentVar"
}

Write-Output "`r`nDapr CLI is installed successfully."
Write-Output "To get started with Dapr, please visit https://docs.dapr.io/getting-started/ ."
Write-Output "Ensure that Docker Desktop is set to Linux containers mode when you run Dapr in self hosted mode."
