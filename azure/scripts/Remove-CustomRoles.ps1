param (
    [string]$Scope = "/providers/Microsoft.Management/managementGroups/libredevops",
    [array]$RoleDefinitions = @(
    "[LIBREDEVOPS] Network-Management"
)
)

function Remove-AzCustomRoles
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Scope,
        [Parameter(Mandatory = $true)]
        [array]$RoleDefinitions
    )

    foreach ($role in $RoleDefinitions)
    {
        $attempt = 0
        while ($attempt -lt 3)
        {
            try
            {
                $attempt++
                Write-Host "Attempt #$attempt to remove role definition: $role" -ForegroundColor Yellow
                Get-AzRoleDefinition -Name $role -Scope $Scope | Remove-AzRoleDefinition -Force -Confirm:$false

                # Check immediately if the role has been deleted
                $roleCheck = Get-AzRoleDefinition -Name $role -Scope $Scope -ErrorAction SilentlyContinue
                if ($null -eq $roleCheck)
                {
                    Write-Host "Successfully removed role definition: $role" -ForegroundColor Green
                    break # Exit the loop as the role has been successfully removed
                }
                else
                {
                    $waitTime = $attempt * 10
                    Write-Host "Role definition $role still exists. Trying again in $waitTime seconds." -ForegroundColor Red
                    Start-Sleep -Seconds $waitTime
                }
            }
            catch
            {
                $waitTime = $attempt * 10
                Write-Host "Attempt #$attempt failed. Error: $( $_.Exception.Message )" -ForegroundColor Red
                if ($attempt -eq 3)
                {
                    Write-Host "Failed to remove role definition: $role after 3 attempts." -ForegroundColor Red
                }
                else
                {
                    Write-Host "Trying again in $waitTime seconds." -ForegroundColor Red
                    Start-Sleep -Seconds $waitTime
                }
            }
        }
    }
}

Remove-AzCustomRoles -Scope $Scope -RoleDefinitions $RoleDefinitions
