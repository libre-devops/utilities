#!/usr/bin/env bash

##############################################################################
# Set safe defaults
##############################################################################
set -euo pipefail

##############################################################################
# Default parameter values
##############################################################################
UseServicePrincipal=false
ClientId=""
TenantId=""
ClientSecret=""
SubscriptionId=""
FedToken=""       # Not used in current logic, but included for completeness
IsDebugMode=false

##############################################################################
# CLI argument parsing
#   You can supply:
#     --use-service-principal (true|false)
#     --client-id <string>
#     --tenant-id <string>
#     --client-secret <string>
#     --subscription-id <string>
#     --fed-token <string>
#     --debug (true|false)
##############################################################################
while [[ $# -gt 0 ]]; do
  case $1 in
    --use-service-principal)
      UseServicePrincipal="$2"
      shift 2
      ;;
    --client-id)
      ClientId="$2"
      shift 2
      ;;
    --tenant-id)
      TenantId="$2"
      shift 2
      ;;
    --client-secret)
      ClientSecret="$2"
      shift 2
      ;;
    --subscription-id)
      SubscriptionId="$2"
      shift 2
      ;;
    --fed-token)
      FedToken="$2"
      shift 2
      ;;
    --debug)
      IsDebugMode="$2"
      shift 2
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

##############################################################################
# Simple colour definitions for console output
##############################################################################
COLOUR_RED='\033[0;31m'
COLOUR_YELLOW='\033[0;33m'
COLOUR_CYAN='\033[0;36m'
COLOUR_RESET='\033[0m'

##############################################################################
# _LogMessage function
#   Usage: _LogMessage "DEBUG|INFO|WARNING|ERROR" "Message text" "InvocationName"
##############################################################################
_LogMessage() {
  local Level="$1"
  local Message="$2"
  local InvocationName="$3"
  local timestamp
  timestamp="$(date +"%H:%M:%S")"

  # If it's a DEBUG message but debug mode is off, skip
  if [[ "$Level" == "DEBUG" && "$IsDebugMode" != "true" ]]; then
    return
  fi

  local prefix="${Level}: ${timestamp} - [${InvocationName}]"

  case "$Level" in
    "INFO")
      echo -e "${COLOUR_CYAN}${prefix} ${Message}${COLOUR_RESET}"
      ;;
    "DEBUG")
      echo -e "${COLOUR_YELLOW}${prefix} ${Message}${COLOUR_RESET}"
      ;;
    "WARNING")
      echo -e "${COLOUR_YELLOW}${prefix} ${Message}${COLOUR_RESET}"
      ;;
    "ERROR")
      echo -e "${COLOUR_RED}${prefix} ${Message}${COLOUR_RESET}"
      ;;
    *)
      echo -e "${prefix} ${Message}"
      ;;
  esac
}

##############################################################################
# Connect-AzureUser
#   1. Check if already logged in (az account show).
#   2. If not, do az login (interactive).
#   3. If SubscriptionId is set, do az account set.
##############################################################################
Connect-AzureUser() {
  local InvocationName="Connect-AzureUser"

  # Try to see if we have an existing login
  if ! az account show --output json &>/dev/null; then
    # Not logged in; do interactive login
    _LogMessage "INFO" "No existing Azure CLI login found. Authenticating (interactive)..." "$InvocationName"
    if ! output=$(az login 2>&1); then
      _LogMessage "ERROR" "Authentication failed: $output" "$InvocationName"
      return 1
    fi
    _LogMessage "INFO" "Authentication successful." "$InvocationName"

    if [[ -n "$SubscriptionId" ]]; then
      _LogMessage "INFO" "Setting subscription to $SubscriptionId..." "$InvocationName"
      if ! sub_output=$(az account set --subscription "$SubscriptionId" 2>&1); then
        _LogMessage "ERROR" "Subscription set failed: $sub_output" "$InvocationName"
        return 1
      fi
    fi
  else
    # Already logged in
    local currentUser
    currentUser=$(az account show --output tsv --query user.name 2>/dev/null || echo "")
    _LogMessage "INFO" "Already authenticated to Azure CLI as $currentUser." "$InvocationName"
  fi
}

##############################################################################
# Connect-ToAzureSpn
#   1. If UseServicePrincipal == true, do az login --service-principal.
#   2. Otherwise, call Connect-AzureUser for interactive approach.
#   3. If SubscriptionId is set, do az account set.
##############################################################################
Connect-ToAzureSpn() {
  local UseSPN="$1"
  local ClientId="$2"
  local TenantId="$3"
  local ClientSecret="$4"
  local FedToken="$5"    # not used, but we keep for structure
  local InvocationName="Connect-ToAzureSpn"

  if [[ "$UseSPN" == "true" ]]; then
    _LogMessage "INFO" "Connecting with Service Principal (Client Secret flow)..." "$InvocationName"
    if ! spn_output=$(az login \
      --service-principal \
      --username "$ClientId" \
      --password "$ClientSecret" \
      --tenant "$TenantId" 2>&1); then
      _LogMessage "ERROR" "Service principal authentication failed: $spn_output" "$InvocationName"
      return 1
    fi

    if [[ -n "$SubscriptionId" ]]; then
      _LogMessage "INFO" "Setting subscription to $SubscriptionId..." "$InvocationName"
      if ! sub_output=$(az account set --subscription "$SubscriptionId" 2>&1); then
        _LogMessage "ERROR" "Subscription set failed: $sub_output" "$InvocationName"
        return 1
      fi
    fi

  elif [[ "$UseSPN" == "false" ]]; then
    Connect-AzureUser
  else
    _LogMessage "ERROR" "Invalid authentication combination. Check parameters." "$InvocationName"
    return 1
  fi
}

##############################################################################
# Main Logic
##############################################################################
main() {
  local InvocationName="main"
  _LogMessage "INFO" "Starting script..." "$InvocationName"

  # 1. Connect to Azure using Azure CLI
  if ! Connect-ToAzureSpn "$UseServicePrincipal" "$ClientId" "$TenantId" "$ClientSecret" "$FedToken"; then
    _LogMessage "ERROR" "A terminating error occurred during Connect-ToAzureSpn." "$InvocationName"
    exit 1
  fi
}

main "$@"
