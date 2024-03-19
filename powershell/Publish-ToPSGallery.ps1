$nugetToken = $Env:ps_gallery_token

$module = './LibreDevOpsUtils.psd1'
$version = '1.0.0'

Update-ModuleManifest -Path ./LibreDevOpsUtils.psd1 -FunctionsToExport (Get-Command -Module LibreDevOpsUtils).Name
Publish-Module -Name $module -RequiredVersion $version -Force -NuGetApiKey $nugetToken
