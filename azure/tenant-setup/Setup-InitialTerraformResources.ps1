#!/usr/bin/env pwsh

    [Diagnostics.CodeAnalysis.SuppressMessage("PSAvoidUsingInvokeExpression", "")]
    [CmdletBinding()]
param(
    [switch]$Help,
    [bool]$AttemptSubscriptionRoleAssignments = $true,
    [bool]$AttemptManagementGroupRoleAssignments = $false

)

try
{
    $ErrorActionPreference = 'Stop'

    function Show-InitialMessage
    {
        Write-Host "This script is intended to be run in a PowerShell environment to set up your pre-requisite items in a fresh tenant, to setup management resources for terraform. You will need Owner in Tenant Root Group (or similar), Global Administrator in Microsoft Entra for ID, Key Vault Administrator to manage Key Vault, and Storage Blob Data Owner for Storage account management. This is just an example to get going, please review any code before you run it!" -ForegroundColor Black -BackgroundColor Yellow
        Start-Sleep -Seconds 0
    }

    function Set-StrictModeLatest
    {
        Set-StrictMode -Version Latest
    }

    function Initialize-Variables
    {
        $global:SubscriptionId = "sub-ldo-uks-prd-mgmt-01"
        $global:ShorthandName = "lbd"
        $global:ShorthandLocation = "uks"
        $global:ShorthandEnv = "prd6"
        Determine-LonghandLocation
        Convert-ShorthandNames
        Set-ResourceObjectNames
    }

    function Determine-LonghandLocation
    {
        $locationMap = @{
            "uks" = "uksouth"
            "ukw" = "ukwest"
            "euw" = "westeurope"
            "eun" = "northeurope"
            "use" = "eastus"
            "use2" = "eastus2"
        }
        $global:LonghandLocation = $locationMap[$global:ShorthandLocation]
    }

    function Convert-ShorthandNames
    {
        $global:lowerConvertedShorthandName = $global:ShorthandName.ToLower()
        $global:lowerConvertedShorthandEnv = $global:ShorthandEnv.ToLower()
        $global:lowerConvertedShorthandLocation = $global:ShorthandLocation.ToLower()
        $TextInfo = (Get-Culture).TextInfo
        $global:titleConvertedShorthandName = $TextInfo.ToTitleCase($global:ShorthandName)
        $global:titleConvertedShorthandEnv = $TextInfo.ToTitleCase($global:ShorthandEnv)
        $global:titleConvertedShorthandLocation = $TextInfo.ToTitleCase($global:ShorthandLocation)
    }

    function Set-ResourceObjectNames
    {
        $global:ResourceGroupName = "rg-${global:lowerConvertedShorthandName}-${global:lowerConvertedShorthandLocation}-${global:lowerConvertedShorthandEnv}-mgmt"
        $global:KeyvaultName = "kv-${global:lowerConvertedShorthandName}-${global:lowerConvertedShorthandLocation}-${global:lowerConvertedShorthandEnv}-mgmt-01"
        $global:ServicePrincipalName = "svp-${global:lowerConvertedShorthandName}-${global:lowerConvertedShorthandLocation}-${global:lowerConvertedShorthandEnv}-mgmt-01"
        $global:ManagedIdentityName = "id-${global:lowerConvertedShorthandName}-${global:lowerConvertedShorthandLocation}-${global:lowerConvertedShorthandEnv}-mgmt-01"
        $global:PublicSshKeyName = "ssh-${global:lowerConvertedShorthandName}-${global:lowerConvertedShorthandLocation}-${global:lowerConvertedShorthandEnv}-pub-mgmt"
        $global:PrivateSshKeyName = "Ssh${global:titleConvertedShorthandName}${global:titleConvertedShorthandLocation}${global:titleConvertedShorthandEnv}Key"
        $global:StorageAccountName = "sa${global:lowerConvertedShorthandName}${global:lowerConvertedShorthandLocation}${global:lowerConvertedShorthandEnv}mgmt01"
        $global:BlobContainerName = "blob${global:lowerConvertedShorthandName}${global:lowerConvertedShorthandLocation}${global:lowerConvertedShorthandEnv}mgmt01"
    }

    function Validate-AzModules
    {
        $TestCommands = @(
            'Get-AzContext',
            'Set-AzContext',
            'New-AzResourceGroup',
            'New-AzKeyVault',
            'Get-AzKeyvault',
            'Set-AzKeyVaultAccessPolicy',
            'Set-AzKeyVaultSecret',
            'Get-AzADUser',
            'Get-AzADServicePrincipal',
            'New-AzADServicePrincipal',
            'Get-AzUserAssignedIdentity',
            'New-AzSshKey',
            'New-AzStorageAccount',
            'New-AzStorageContainer'
        )
        foreach ($command in $TestCommands)
        {
            if (-not(Get-Command $command -ErrorAction SilentlyContinue))
            {
                Write-Host "$command doesn't exist, it requires to be installed for this script to continue. Try - Install-Module -Name Az.Accounts -AllowClobber or pwsh -Command Install-Module -Name Az -Force -AllowClobber -Scope AllUsers -Repository PSGallery.  - Exit Code - AZ_CMDS_NOT_INSTALLED" -ForegroundColor Black -BackgroundColor Yellow
                exit 1
            }
        }
    }

    function Ensure-LoggedIn
    {
        $LoggedIn = Get-AzContext
        if ($null -eq $LoggedIn)
        {
            Write-Host "You need to login to Azure to run this script" -ForegroundColor Black -BackgroundColor Red
            exit 1
        }
        else
        {
            Write-Host "Already logged in, continuing..." -ForegroundColor Black -BackgroundColor Green
        }
    }

    function Validate-UserRoles
    {
        $currentUserObjectId = $( Get-AzADUser ).id
        $roleAssignments = Get-AzRoleAssignment -ObjectId $currentUserObjectId
        $requiredRoles = @("Owner", "Key Vault Administrator", "Storage Blob Data Owner")
        $missingRoles = @($requiredRoles | Where-Object { $_ -notin $roleAssignments.RoleDefinitionName })
        if ($missingRoles.Count -gt 0)
        {
            $errorMessage = "The user lacks the following roles in the current subscription: $( $missingRoles -join ', ' )"
            Write-Error $errorMessage
            exit 1
        }
        else
        {
            Write-Host "The user has all required AzureRm RBAC roles in the current subscription to run this script." -ForegroundColor Green
        }
    }

    function Validate-ShorthandName
    {
        if (-not($ShorthandName.Length -le 5 -and $ShorthandName.Length -ge 1))
        {
            Write-Host "You can't have a shorthand greater than 5, edit the variables and retry" -ForegroundColor Black -BackgroundColor Red
            exit 1
        }
        else
        {
            Write-Host "${lowerConvertedShorthandName} shorthand name is less than 5 and greater than 1, thus is permissible, continuing" -ForegroundColor Black -BackgroundColor Green
        }
    }

    function Add-SecretToKeyVault
    {
        param (
            [string]$SecretName,
            [string]$SecretValue
        )

        $secureSecret = ConvertTo-SecureString -String $SecretValue -AsPlainText -Force
        Set-AzKeyVaultSecret -VaultName $global:KeyvaultName -Name $SecretName -SecretValue $secureSecret
    }

    function Store-PSObjectInKeyVault
    {
        param (
            [psobject]$PSObject
        )

        # Define a list of properties to ignore
        $ignoreProperties = @('Count', 'IsFixedSize', 'IsReadOnly', 'IsSynchronized', 'Keys', 'Values', 'SyncRoot')

        $properties = $PSObject.PSObject.Properties | Where-Object {
            $_.Name -notin $ignoreProperties
        }

        foreach ($property in $properties)
        {
            $value = $property.Value
            Write-Host "Storing key $( $property.Name ), value is ${value}"
            Add-SecretToKeyVault -SecretName $property.Name -SecretValue $value
        }
    }


    function Get-AzureDetails
    {
        param (
            [bool]$AddOutputsToKeyvault = $true
        )
        $SubId = (Get-AzContext).Subscription
        $signedInUserUpn = (Get-AzADUser -SignedIn).Id
        $signedInTenantId = (Get-AzContext).Tenant.Id # Corrected to directly access the Tenant ID

        $azureDetails = New-Object PSObject -Property @{
            "SpokeSubscriptionId" = $SubId
            "CreatedUserObjectId" = $signedInUserUpn
            "SpokeTenantId" = $signedInTenantId
        }

        if ($AddOutputsToKeyvault -eq $true)
        {
            Store-PSObjectInKeyVault -PSObject $azureDetails
        }

        return $azureDetails
    }

    function Create-ResourceGroup
    {
        param (
            [bool]$AddOutputsToKeyvault = $true
        )
        $resourceGroup = Get-AzResourceGroup -Name $global:ResourceGroupName -ErrorAction SilentlyContinue
        if (-not$resourceGroup)
        {
            Write-Host "Creating Resource Group '$global:ResourceGroupName' in location '$global:LonghandLocation'."
            $resourceGroup = New-AzResourceGroup -Name $global:ResourceGroupName -Location $global:LonghandLocation
            Write-Host "Resource Group '$global:ResourceGroupName' created."
        }
        else
        {
            Write-Host "Resource Group '$global:ResourceGroupName' already exists."
        }

        # Create and return an object with rgName and rgId
        $resourceGroupDetails = New-Object PSObject -Property @{
            "SpokeMgmtRgName" = $resourceGroup.ResourceGroupName
            "SpokeMgmtRgId" = $resourceGroup.ResourceId
        }

        if ($AddOutputsToKeyvault -eq $true)
        {
            Store-PSObjectInKeyVault -PSObject $resourceGroupDetails
        }


        return $resourceGroupDetails
    }


    function Create-KeyVault
    {
        param (
            [bool]$AddOutputsToKeyvault = $true
        )
        $keyVault = Get-AzKeyVault -VaultName $global:KeyvaultName -ErrorAction SilentlyContinue
        if (-not$keyVault)
        {
            Write-Host "Keyvault '$global:KeyvaultName' doesn't exist, creating it."
            $keyVault = New-AzKeyVault -Name $global:KeyvaultName -ResourceGroupName $global:ResourceGroupName -Location $global:LonghandLocation -EnableRbacAuthorization
            Write-Host "Keyvault '$global:KeyvaultName' created."
        }
        else
        {
            Write-Host "Keyvault '$global:KeyvaultName' already exists."
        }

        # Create and return an object with id, uri, and name
        $keyVaultDetails = New-Object PSObject -Property @{
            "SpokeKeyvaultId" = $keyVault.ResourceId
            "SpokeKeyvaultUri" = $keyVault.VaultUri
            "SpokeKeyvaultName" = $keyVault.VaultName
        }

        if ($AddOutputsToKeyvault -eq $true)
        {
            Write-Host "Waiting 30 seconds to allow key vault to create"
            Start-Sleep -Seconds 30
            Store-PSObjectInKeyVault -PSObject $keyVaultDetails
        }
        return $keyVaultDetails
    }


    function Configure-ServicePrincipal
    {
        param (
            [bool]$AddOutputsToKeyvault = $true
        )
        $servicePrincipalExists = Get-AzADServicePrincipal -DisplayName $global:ServicePrincipalName -ErrorAction SilentlyContinue
        if (-not$servicePrincipalExists)
        {
            Write-Host "Service Principal '$global:ServicePrincipalName' does not exist, creating now."
            $sp = New-AzADServicePrincipal -DisplayName $global:ServicePrincipalName
            $spClientId = $sp.AppId
            $spClientSecret = ($sp.PasswordCredentials | Select-Object -First 1).SecretText
            $spId = $sp.Id
            $spTenantId = $sp.AppOwnerOrganizationId
            $spDetails = New-Object PSObject -Property @{
                "SpokeSvpApplicationId" = $spClientId
                "SpokeSvpObjectId" = $spId
                "SpokeSvpClientSecret" = $spClientSecret
                "SpokeSvpTenantId" = $spTenantId
            }
        }
        else
        {
            Write-Host "Service Principal '$global:ServicePrincipalName' already exists."
            $sp = Get-AzADServicePrincipal -DisplayName $global:ServicePrincipalName
            $spClientId = $sp.AppId
            $spClientSecret = ($sp.PasswordCredentials | Select-Object -First 1).SecretText
            $spId = $sp.Id
            $spTenantId = $sp.AppOwnerOrganizationId
            $spDetails = New-Object PSObject -Property @{
                "SpokeSvpApplicationId" = $spClientId
                "SpokeSvpObjectId" = $spId
                "SpokeSvpClientSecret" = $spClientSecret -ne $null ? $spClientSecret : "Secret not retrievable for existing Service Principal"
            }
        }

        if ($AddOutputsToKeyvault -eq $true)
        {
            Write-Host "Sleeping 15s to allow SPN to sync to directory"
            Start-Sleep -Seconds 15
            Store-PSObjectInKeyVault -PSObject $spDetails
        }

        return $spDetails
    }

    function Create-ManagedIdentity
    {
        param (
            [bool]$AddOutputsToKeyvault = $true
        )
        $managedIdentityExists = Get-AzUserAssignedIdentity -ResourceGroupName $global:ResourceGroupName -Name $global:ManagedIdentityName -ErrorAction SilentlyContinue
        if (-not$managedIdentityExists)
        {
            Write-Host "Managed Identity '$global:ManagedIdentityName' does not exist, creating it."
            $mi = New-AzUserAssignedIdentity -ResourceGroupName $global:ResourceGroupName -Name $global:ManagedIdentityName -Location $global:LonghandLocation
            Write-Host "Managed Identity '$global:ManagedIdentityName' created."
        }
        else
        {
            Write-Host "Managed Identity '$global:ManagedIdentityName' already exists."
            $mi = $managedIdentityExists
        }

        # Create and return an object with managed identity details
        $miDetails = [PSCustomObject]@{
            "SpokeUmiId" = $mi.Id
            "SpokeUmiName" = $mi.Name
            "SpokeUmiObjectId" = $mi.PrincipalId
            "SpokeUmiTenantId" = $mi.TenantId
        }

        if ($AddOutputsToKeyvault -eq $true)
        {
            Store-PSObjectInKeyVault -PSObject $miDetails
        }

        return $miDetails
    }


    function Create-StorageAccountAndBlobContainer
    {
        param (
            [bool]$AddOutputsToKeyvault = $true
        )
        $storageAccountExists = Get-AzStorageAccount -ResourceGroupName $global:ResourceGroupName -Name $global:StorageAccountName -ErrorAction SilentlyContinue
        if (-not$storageAccountExists)
        {
            Write-Host "Storage account '$global:StorageAccountName' doesn't exist, creating it."
            $sa = New-AzStorageAccount -ResourceGroupName $global:ResourceGroupName -Name $global:StorageAccountName -Location $global:LonghandLocation -SkuName "Standard_LRS" -AllowBlobPublicAccess $false
            $context = New-AzStorageContext -StorageAccountName $sa.StorageAccountName -StorageAccountKey ($sa | Get-AzStorageAccountKey | Select -First 1).Value
            $container = New-AzStorageContainer -Name $global:BlobContainerName -Context $context -Permission Off
            Write-Host "Storage account and blob container '$global:BlobContainerName' created."
        }
        else
        {
            Write-Host "Storage account '$global:StorageAccountName' already exists."
            $sa = $storageAccountExists
        }
        $keys = Get-AzStorageAccountKey -ResourceGroupName $global:ResourceGroupName -AccountName $sa.StorageAccountName
        $saDetails = [PSCustomObject]@{
            "SpokeSaName" = $sa.StorageAccountName
            "SpokeSaBlobContainerName" = $global:BlobContainerName
            "SpokeSaKey1" = $keys[0].Value
            "SpokeSaKey2" = $keys[1].Value
            "SpokeSaId" = $sa.Id
        }

        if ($AddOutputsToKeyvault -eq $true)
        {
            Store-PSObjectInKeyVault -PSObject $saDetails
        }

        return $saDetails
    }

    function Create-SSHKeys
    {
        param (
            [bool]$AddOutputsToKeyvault = $true
        )
        $sshKeyName = $PublicSshKeyName
        $sshKeyDirectory = "$env:HOME/.ssh"
        $sshKeyPath = "$sshKeyDirectory/$sshKeyName"
        $publicKeyPath = "$sshKeyPath.pub"

        if (-not(Test-Path $sshKeyDirectory))
        {
            Write-Host "Creating .ssh directory at $sshKeyDirectory"
            New-Item -ItemType Directory -Path $sshKeyDirectory | Out-Null
        }

        if (-not(Test-Path $publicKeyPath))
        {
            Write-Host "Generating SSH Keys at $sshKeyPath"
            ssh-keygen -t rsa -b 4096 -f $sshKeyPath -N '' -q
            Write-Host "SSH key pair $sshKeyName generated successfully."
        }
        else
        {
            Write-Host "SSH key pair $sshKeyName already exists."
        }

        # Check if the public key exists
        if (Test-Path $publicKeyPath)
        {
            $publicKeyContent = Get-Content $publicKeyPath -Raw
            $privateKeyContent = Get-Content $sshKeyPath -Raw

            # Assuming $ResourceGroupName and $PublicSshKeyName are defined globally or passed to the function
            $PublicSshKeyName = $sshKeyName # You may adjust this as needed

            # Check if the Azure SSH key already exists
            $existingSshKey = Get-AzSshKey -ResourceGroupName $ResourceGroupName -Name $PublicSshKeyName -ErrorAction SilentlyContinue
            if (-not$existingSshKey)
            {
                Write-Host "Creating Azure SSH Key resource with name $PublicSshKeyName in resource group $ResourceGroupName"
                $SshKey = New-AzSshKey -ResourceGroupName $ResourceGroupName -Name $PublicSshKeyName -PublicKey $publicKeyContent

                $sshKeysDetails = @{
                    "SpokeSshPublicKey" = $publicKeyContent
                    "SpokeSshPrivateKey" = $privateKeyContent
                    "SpokeSshKeyId" = $SshKey.Id
                }

                if ($AddOutputsToKeyvault -eq $true)
                {
                    Store-PSObjectInKeyVault -PSObject $sshKeysDetails
                }

                return $sshKeysDetails
            }
            else
            {
                Write-Host "Azure SSH key $PublicSshKeyName already exists in resource group $ResourceGroupName."
            }
        }
        else
        {
            Write-Host "Error: Public key not found at $publicKeyPath"
        }

        # Return the SSH key details even if it already exists
        $sshKeysDetails = @{
            "SpokeSshPublicKey" = $publicKeyContent
            "SpokeSshPrivateKey" = $privateKeyContent
            "SpokeSshKeyId" = $SshKey.Id
        }

        if ($AddOutputsToKeyvault -eq $true)
        {
            Store-PSObjectInKeyVault -PSObject $sshKeysDetails
        }

        return $sshKeysDetails
    }

    function Try-SubscripionRoleAssignments
    {
        param (
            [string]$SvpObjectId,
            [string]$UmiObjectId,
            [string]$RoleDefinitionName = "Owner",
            [string]$SubscriptionId
        )
        New-AzRoleAssignment `
        -ObjectId $SvpObjectId `
        -RoleDefinitionName $RoleDefinitionName `
        -Scope "/subscriptions/${SubscriptionId}"

        New-AzRoleAssignment `
        -ObjectId $UmiObjectId `
        -RoleDefinitionName $RoleDefinitionName `
        -Scope "/subscriptions/${SubscriptionId}"
    }

    function Try-ManagementGroupRoleAssignments
    {
        param (
            [string]$SvpObjectId,
            [string]$UmiObjectId,
            [string]$RoleDefinitionName = "Owner",
            [string]$ManagementGroup
        )
        New-AzRoleAssignment `
        -ObjectId $SvpObjectId `
        -RoleDefinitionName $RoleDefinitionName `
        -Scope $ManagementGroup

        New-AzRoleAssignment `
        -ObjectId $UmiObjectId `
        -RoleDefinitionName $RoleDefinitionName `
        -Scope $ManagementGroup
    }

    Show-InitialMessage
    Set-StrictModeLatest
    Initialize-Variables
    Validate-AzModules
    Ensure-LoggedIn
    Validate-UserRoles
    Validate-ShorthandName
    $RgDetails = Create-ResourceGroup -AddOutputsToKeyvault $false
    $AzureDetails = Get-AzureDetails -AddOutputsToKeyvault $false
    Create-KeyVault
    Store-PSObjectInKeyVault $RgDetails
    Get-AzureDetails
    Configure-ServicePrincipal
    Create-ManagedIdentity
    Create-StorageAccountAndBlobContainer
    Create-SSHKeys

    if ($true -eq $AttemptSubscriptionRoleAssignments)
    {
        $SvpDetails = Configure-ServicePrincipal -AddOutputsToKeyvault $false
        $UmiDetails = Create-ManagedIdentity -AddOutputsToKeyvault $false

        $assignmentRoles = @("Owner", "Key Vault Administrator", "Storage Blob Data Owner")
        foreach ($role in $assignmentRoles)
        {
            Try-SubscripionRoleAssignments `
                -SvpObjectId $SvpDetails.SpokeSvpObjectId `
                -UmiObjectId $UmiDetails.SpokeUmiObjectId `
                -SubscriptionId $AzureDetails.SpokeSubscriptionId `
                -RoleDefinitionName $role

        }
    }
    if ($true -eq $AttemptManagementGroupRoleAssignments)
    {
        $SvpDetails = Configure-ServicePrincipal -AddOutputsToKeyvault $false
        $UmiDetails = Create-ManagedIdentity -AddOutputsToKeyvault $false

        $assignmentRoles = @("Owner", "Key Vault Administrator", "Storage Blob Data Owner")
        foreach ($role in $assignmentRoles)
        {
            Try-ManagementGroupRoleAssignments `
                -SvpObjectId $SvpDetails.SpokeSvpObjectId `
                -UmiObjectId $UmiDetails.SpokeUmiObjectId `
                -ManagementGroup "/" `
                -RoleDefinitionName $role

        }
    }
 }
catch
{
    throw "[$( $MyInvocation.MyCommand.Name )] Error: An error has occured in the script:  $_"
    exit 1
}
