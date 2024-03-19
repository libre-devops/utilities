$username = $Env:registry_username
$token = $Env:registry_password

$sourceName = 'GitHub'
$source = "https://nuget.pkg.github.com/$username/index.json"
$moduleName = "LibreDevOpsUtils"

Set-PSRepository -Name "GitHub" -SourceLocation $source -InstallationPolicy Trusted

#Register-PSRepository -Name github -SourceLocation https://nuget.pkg.github.com/$username/index.json
$securePwd = ConvertTo-SecureString $token -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential ($username, $securePwd)
Install-PSResource -Name $moduleName -Repository github -Credential $credentials

## Create a PSCredential object for authentication
#$secureToken = $token | ConvertTo-SecureString -AsPlainText -Force
#$creds = New-Object System.Management.Automation.PSCredential ($username, $secureToken)
#
## Register the GitHub package registry as a PowerShell repository
#Register-PSRepository -Name $sourceName -SourceLocation $source -PublishLocation $source -InstallationPolicy Trusted -Credential $creds
#
## Install the module from the registered repository
#Install-Module -Name $moduleName -Repository $sourceName -Credential $creds -AllowClobber -Force
