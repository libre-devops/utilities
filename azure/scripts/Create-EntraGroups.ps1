<#
.SYNOPSIS
    This script creates Microsoft Entra (Azure AD) security groups following the structure Az-${SubscriptionOrResourceGroupName}-${Environment}-${AzurePermission}.

    Example:
    ./New-EntraGroups.ps1 -SubscriptionOrResourceGroupName "Libre-DevOps", "CyberScot" -AzurePermission "Owners" -Environment "Dev"
    This will create a group with the name: Az-Libre-DevOps-Dev-Owners & Az-CyberScot-Owners-Dev

.DESCRIPTION
    This script authenticates to Azure AD and creates security groups based on provided inputs for the subscription/resource group name, environment, and permission level.
    It supports a debug mode for additional output and includes error handling.

.REQUIREMENTS
    - Azure PowerShell Module (Az.Accounts and Az.Resources)
    - Permissions to create security groups in Azure AD

.PARAMETER SubscriptionOrResourceGroupName
    The name of the subscription or resource group that forms part of the group name.

.PARAMETER AzurePermission
    The permission level (e.g., Owners, Contributors, Readers) that forms part of the group name.

.PARAMETER Environment
    (Optional) The environment (e.g., Dev, Prod) that forms part of the group name. Defaults to 'Dev'.

.PARAMETER DebugMode
    Enables debug mode for detailed output.

.NOTES
    Author: Craig Thacker
    Date: 26 September 2024
#>

#Requires -Modules Az.Accounts, Az.Resources
param (
    [Parameter(Mandatory = $true)]
    [string[]]$SubscriptionOrResourceGroupName,  # Subscription or resource group name
    [Parameter(Mandatory = $true)]
    [string]$AzurePermission,  # Permission level like Owners, Contributors, Readers
    [Parameter(Mandatory = $true)]
    [string]$Environment,
    [switch]$DebugMode
)

# Global variable to control whether debug logs are shown
$IsDebugMode = $DebugMode.IsPresent

function _LogMessage {
    param (
        [string]$Level,
        [string]$Message,
        [string]$InvocationName = $MyInvocation.MyCommand.Name
    )
    $timestamp = Get-Date -Format "HH:mm:ss"

    # Only log debug messages if DebugMode is enabled
    if ($Level -eq "DEBUG" -and -not $IsDebugMode) {
        return  # Don't log debug messages if DebugMode is not enabled
    }

    switch ($Level) {
        "INFO" {
            Write-Host "$($Level): $timestamp - [$InvocationName] $Message" -ForegroundColor Cyan
        }
        "DEBUG" {
            Write-Host "$($Level): $timestamp - [$InvocationName] $Message" -ForegroundColor Yellow
        }
        "ERROR" {
            Write-Host "$($Level): $timestamp - [$InvocationName] $Message" -ForegroundColor Red
        }
        default {
            Write-Host "$($Level): $timestamp - [$InvocationName] $Message"
        }
    }
}

function Connect-Azure {
    <#
    .SYNOPSIS
        Authenticates to Azure using the Azure PowerShell module if not already authenticated.
    #>
    try {
        # Check if the user is already authenticated
        $context = Get-AzContext
        if ($null -eq $context -or $null -eq $context.Account) {
            _LogMessage -Level "INFO" -Message "No existing Azure context found. Authenticating to Azure..." -InvocationName $MyInvocation.MyCommand.Name
            Connect-AzAccount -ErrorAction Stop
            _LogMessage -Level "INFO" -Message "Authentication successful." -InvocationName $MyInvocation.MyCommand.Name
        }
        else {
            _LogMessage -Level "INFO" -Message "Already authenticated to Azure as $($context.Account.Id)." -InvocationName $MyInvocation.MyCommand.Name
        }
    }
    catch {
        _LogMessage -Level "ERROR" -Message "Authentication failed. $_" -InvocationName $MyInvocation.MyCommand.Name
        throw
    }
}

function Assert-GroupExists {
    param (
        [string]$GroupName
    )
    <#
    .SYNOPSIS
        Checks if a group with the given display name already exists.
    .PARAMETER GroupName
        The name of the group to check.
    #>
    try {
        $existingGroup = Get-AzADGroup -DisplayName $GroupName -ErrorAction SilentlyContinue
        if ($null -ne $existingGroup) {
            _LogMessage -Level "ERROR" -Message "A group with the name '$GroupName' already exists. Aborting creation." -InvocationName $MyInvocation.MyCommand.Name
            throw "Group '$GroupName' already exists."
        } else {
            _LogMessage -Level "DEBUG" -Message "No existing group found with the name '$GroupName'." -InvocationName $MyInvocation.MyCommand.Name
        }
    }
    catch {
        _LogMessage -Level "ERROR" -Message "Failed to check if group '$GroupName' exists. $_" -InvocationName $MyInvocation.MyCommand.Name
        throw
    }
}

function New-EntraSecurityGroup {
    param (
        [string]$GroupName
    )
    <#
    .SYNOPSIS
        Creates a Microsoft Entra (Azure AD) security group.
    .PARAMETER GroupName
        The name of the group to create.
    #>
    try {
        _LogMessage -Level "INFO" -Message "Creating group: $GroupName" -InvocationName $MyInvocation.MyCommand.Name
        $groupParams = @{
            DisplayName = $GroupName
            MailEnabled = $false
            SecurityEnabled = $true
            MailNickname = $GroupName
        }
        _LogMessage -Level "DEBUG" -Message "Creating group with parameters: $($groupParams | Out-String)" -InvocationName $MyInvocation.MyCommand.Name

        New-AzADGroup @groupParams -ErrorAction Stop
        _LogMessage -Level "INFO" -Message "Group '$GroupName' created successfully." -InvocationName $MyInvocation.MyCommand.Name
    }
    catch {
        _LogMessage -Level "ERROR" -Message "Failed to create group '$GroupName'. Error: $_" -InvocationName $MyInvocation.MyCommand.Name
    }
}

# Set logging preferences based on DebugMode
if ($DebugMode) {
    $DebugPreference = "Continue"
    $InformationPreference = "Continue"
    _LogMessage -Level "DEBUG" -Message "Debug mode is enabled. All logs will be displayed."
} else {
    $DebugPreference = "SilentlyContinue"
    $InformationPreference = "SilentlyContinue"
}

try {
    # Authenticate to Azure
    Connect-Azure

    # Create groups based on the subscription/resource name, environment, and permission
    foreach ($name in $SubscriptionOrResourceGroupName) {
        $groupName = "Az-$name-$Environment-$AzurePermission"
        _LogMessage -Level "DEBUG" -Message "Processing group: $groupName" -InvocationName $MyInvocation.MyCommand.Name

        # Check if the group already exists
        Assert-GroupExists -GroupName $groupName

        # Create the group if it doesn't exist
        New-EntraSecurityGroup -GroupName $groupName
    }
}
catch {
    _LogMessage -Level "ERROR" -Message "An error occurred in the main flow: $_" -InvocationName $MyInvocation.MyCommand.Name
    _LogMessage -Level "ERROR" -Message "Refresh your credentials if you have not recently authenticated to Azure." -InvocationName $MyInvocation.MyCommand.Name
    throw
}
