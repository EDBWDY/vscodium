param(
    [Parameter(Mandatory = $true)]
    [string]$PreviousProduct,
    [Parameter(Mandatory = $true)]
    [string]$InstalledProduct
)

$ErrorActionPreference = 'Stop'

function Test-DefaultOpenVsxGallery {
    param([object]$Gallery)

    if ($null -eq $Gallery) {
        return $false
    }

    $expected = @{
        serviceUrl = 'https://open-vsx.org/vscode/gallery'
        itemUrl = 'https://open-vsx.org/vscode/item'
        latestUrlTemplate = 'https://open-vsx.org/vscode/gallery/{publisher}/{name}/latest'
        controlUrl = 'https://raw.githubusercontent.com/EclipseFdn/publish-extensions/refs/heads/master/extension-control/extensions.json'
    }
    $properties = @($Gallery.PSObject.Properties)
    if ($properties.Count -ne $expected.Count) {
        return $false
    }

    foreach ($key in $expected.Keys) {
        if ([string]$Gallery.$key -cne $expected[$key]) {
            return $false
        }
    }

    return $true
}

$previous = Get-Content -LiteralPath $PreviousProduct -Raw | ConvertFrom-Json
if ($null -eq $previous.extensionsGallery) {
    exit 0
}

# Fresh installations and normal VSCodium installations retain Open VSX. Any
# non-default gallery is an explicit local override and must survive upgrades.
if (Test-DefaultOpenVsxGallery $previous.extensionsGallery) {
    exit 0
}

$installed = Get-Content -LiteralPath $InstalledProduct -Raw | ConvertFrom-Json
if ($installed.PSObject.Properties.Name -contains 'extensionsGallery') {
    $installed.extensionsGallery = $previous.extensionsGallery
} else {
    $installed | Add-Member -MemberType NoteProperty -Name extensionsGallery -Value $previous.extensionsGallery
}

$temporaryProduct = "$InstalledProduct.marketplace.tmp"
$json = $installed | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($temporaryProduct, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryProduct -Destination $InstalledProduct -Force
