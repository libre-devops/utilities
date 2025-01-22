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
    [string]$FedToken,  # Unused, but left here if you plan to do federated login in future

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
    <#
      Checks if you’re already logged in by calling:
         az account show --output json
      If this fails, we assume no existing context and prompt interactive login.
    #>
    try
    {
        $azContext = $null
        try
        {
            # Attempt to retrieve current context
            $azJson = az account show --output json 2>$null
            if ($LASTEXITCODE -eq 0 -and $azJson)
            {
                $azContext = $azJson | ConvertFrom-Json
            }
        }
        catch
        {
            # Means not currently logged in, so just fall through
        }

        if ($null -eq $azContext)
        {
            _LogMessage -Level "INFO" -Message "No existing Azure CLI login found. Authenticating to Azure (interactive)..." -InvocationName $MyInvocation.MyCommand.Name

            # Interactive login
            $output = az login 2>&1
            if ($LASTEXITCODE -ne 0)
            {
                _LogMessage -Level "ERROR" -Message "Authentication failed: $output" -InvocationName $MyInvocation.MyCommand.Name
                throw "Azure CLI interactive login failed."
            }
            else
            {
                _LogMessage -Level "INFO" -Message "Authentication successful." -InvocationName $MyInvocation.MyCommand.Name
            }

            if ($SubscriptionId)
            {
                _LogMessage -Level "INFO" -Message "Setting subscription to $SubscriptionId..." -InvocationName $MyInvocation.MyCommand.Name
                $output = az account set --subscription $SubscriptionId 2>&1
                if ($LASTEXITCODE -ne 0)
                {
                    _LogMessage -Level "ERROR" -Message "Subscription set failed: $output" -InvocationName $MyInvocation.MyCommand.Name
                    throw "Failed to set subscription."
                }
            }
        }
        else
        {
            # Already logged in – optionally set the subscription
            _LogMessage -Level "INFO" -Message "Already authenticated to Azure CLI as $($azContext.user.name)." -InvocationName $MyInvocation.MyCommand.Name
        }
    }
    catch
    {
        _LogMessage -Level "ERROR" -Message "Authentication failed. $($_.Exception.Message)" -InvocationName $MyInvocation.MyCommand.Name
        throw
    }
}

function Connect-ToAzureSpn
{
    param(
        [bool]$UseSPN,
        [string]$ClientId,
        [string]$TenantId,
        [string]$ClientSecret,
        [string]$FedToken
    )

    if ($UseSPN -eq $true)
    {
        _LogMessage -Level "INFO" -Message "Connecting with Service Principal (Client Secret flow)..." -InvocationName $MyInvocation.MyCommand.Name

        # Perform SP login using Azure CLI
        $output = az login --service-principal --username $ClientId --password $ClientSecret --tenant $TenantId 2>&1
        if ($LASTEXITCODE -ne 0)
        {
            _LogMessage -Level "ERROR" -Message "Service principal authentication failed: $output" -InvocationName $MyInvocation.MyCommand.Name
            throw "Azure CLI SPN login failed."
        }

        if ($SubscriptionId)
        {
            _LogMessage -Level "INFO" -Message "Setting subscription to $SubscriptionId..." -InvocationName $MyInvocation.MyCommand.Name
            $output = az account set --subscription $SubscriptionId 2>&1
            if ($LASTEXITCODE -ne 0)
            {
                _LogMessage -Level "ERROR" -Message "Subscription set failed: $output" -InvocationName $MyInvocation.MyCommand.Name
                throw "Failed to set subscription."
            }
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

#endregion

try
{
    _LogMessage -Level "INFO" -Message "Starting script..." -InvocationName $MyInvocation.MyCommand.Name

    # 1. Connect to Azure using Azure CLI
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
