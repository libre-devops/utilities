<# --
Register the GitHub Package Registry
-- #>
$username = $Env:registry_username
$token = $Env:registry_password

$sourceName = 'GitHub'
$source = "https://nuget.pkg.github.com/$username/index.json"

# add the github package registry as a nuget source
nuget sources Add -Name $sourceName -Source $source -UserName $username -Password $token

# register the github package registry as a powershell repository
$creds = New-Object System.Management.Automation.PSCredential -ArgumentList $username, (ConvertTo-SecureString -AsPlainText $token -Force)
Register-PSRepository -Name $sourceName -SourceLocation $source -PublishLocation $source -Credential $creds


<# --
Publish PowerShell module
-- #>
$module = './LibreDevOpsUtils.psd1'
$version = '1.0.0'
$apiKey = 'n/a' # keep this as n/a!

Update-ModuleManifest -Path ./LibreDevOpsUtils.psd1 -FunctionsToExport (Get-Command -Module LibreDevOpsUtils).Name
Publish-Module -Name $module -Repository $sourceName -RequiredVersion $version -Credential $creds -Force -NuGetApiKey $Env:registry_password
