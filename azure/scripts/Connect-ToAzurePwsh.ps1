param(
    [Parameter(Mandatory = $false)]
    [bool]$UseServicePrincipal = $false,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = $null,

    [Parameter(Mandatory = $false)]
    [switch]$IsDebugMode
)

if ($IsDebugMode)
{
    $IsDebugMode = $true
}
else
{
    $IsDebugMode = $false
}

function _LogMessage
{
    param(
        [string]$Level,
        [string]$Message,
        [string]$InvocationName
    )
    $timestamp = Get-Date -Format "HH:mm:ss"

    if ($Level -eq "DEBUG" -and -not $IsDebugMode)
    {
        return
    }

    switch ($Level)
    {
        "INFO"    {
            Write-Host "$( $Level ): $timestamp - [$InvocationName] $Message" -ForegroundColor Cyan
        }
        "DEBUG"   {
            Write-Host "$( $Level ): $timestamp - [$InvocationName] $Message" -ForegroundColor Yellow
        }
        "WARNING" {
            Write-Host "$( $Level ): $timestamp - [$InvocationName] $Message" -ForegroundColor DarkYellow
        }
        "ERROR"   {
            Write-Host "$( $Level ): $timestamp - [$InvocationName] $Message" -ForegroundColor Red
        }
        default   {
            Write-Host "$( $Level ): $timestamp - [$InvocationName] $Message"
        }
    }
}

#region Auth Functions

function Connect-AzureUser
{
    try
    {
        $context = Get-AzContext
        if ($null -eq $context -or $null -eq $context.Account)
        {
            _LogMessage -Level "INFO" -Message "No existing Azure context found. Authenticating to Azure..." -InvocationName $MyInvocation.MyCommand.Name
            Connect-AzAccount -ErrorAction Stop
            _LogMessage -Level "INFO" -Message "Authentication successful." -InvocationName $MyInvocation.MyCommand.Name

            if ($SubscriptionId)
            {
                _LogMessage -Level "INFO" -Message "Setting subscription to $SubscriptionId..." -InvocationName $MyInvocation.MyCommand.Name
                Set-AzContext -Subscription $SubscriptionId
            }
        }
        else
        {
            _LogMessage -Level "INFO" -Message "Already authenticated to Azure as $( $context.Account.Id )." -InvocationName $MyInvocation.MyCommand.Name
        }
    }
    catch
    {
        _LogMessage -Level "ERROR" -Message "Authentication failed. $( $_.Exception.Message )" -InvocationName $MyInvocation.MyCommand.Name
        throw
    }
}

function Connect-ToAzureSpn
{
    param(
        [bool]$UseSPN,
        [string]$ClientId,
        [string]$TenantId,
        [string]$ClientSecret
    )

    if ($UseSPN -eq $true)
    {
        _LogMessage -Level "INFO" -Message "Connecting with Service Principal (Client Secret flow)..." -InvocationName $MyInvocation.MyCommand.Name
        $securePassword = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($ClientId, $securePassword)
        Connect-AzAccount -ServicePrincipal -Tenant $TenantId -Credential $credential

        if ($SubscriptionId)
        {
            _LogMessage -Level "INFO" -Message "Setting subscription to $SubscriptionId..." -InvocationName $MyInvocation.MyCommand.Name
            Set-AzContext -Subscription $SubscriptionId
        }
    }
    elseif ($UseSPN -eq $false)
    {
        Connect-AzureUser
    }
    else
    {
        _LogMessage -Level "ERROR" -Message "Invalid authentication combination. Check parameters." -InvocationName $MyInvocation.MyCommand.Name
        throw "Invalid authentication method. Use SPN w/ Secret or Interactive User."
    }
}

try
{
    _LogMessage -Level "INFO" -Message "Starting script..." -InvocationName $MyInvocation.MyCommand.Name

    # 1. Connect to Azure
    Connect-ToAzureSpn `
        -UseSPN $UseServicePrincipal `
        -ClientId $ClientId `
        -TenantId $TenantId `
        -ClientSecret $ClientSecret
}
catch
{
    _LogMessage -Level "ERROR" -Message "A terminating error occurred: $( $_.Exception.Message )" -InvocationName $MyInvocation.MyCommand.Name
    exit 1
}
