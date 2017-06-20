#########################################################################
# Password Upload Utility v2
# 
# Description:  Updated Password Upload Utility utilizing the REST API
#               instead of an outdated and restricted version of PACLI
#
# Created by:   Joe Garcia, CISSP
#
# GitHub Repo:  https://github.com/infamousjoeg/PasswordUploadUtility-v2
# 
################## WELCOME TO CYBERARK IMPACT 2017! #####################
#
# TODO:         Add Bulk Change Method
#               Add Additional Properties for non-Windows accounts
#
#########################################################################
# passwords.csv Mapping
#
# Password_name     Object Name
# CPMUser           PasswordManager
# Safe              Safe Name
# Folder            Root
# Password          NO_VALUE
# DeviceType        Operating System
# PolicyID          PlatformID
# Address           Address (IP, DNS, FQDN)
# UserName          Username
##########################################################################

## FUNCTIONS FIRST!
Function OpenFile-Dialog($initialDirectory)
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = "CSV (*.csv)| *.csv"
    $OpenFileDialog.ShowDialog() | Out-Null
    $OpenFileDialog.filename
}

Function PASREST-Logon {

    # Declaration
    $webServicesLogon = "$Global:baseURL/PasswordVault/WebServices/auth/Cyberark/CyberArkAuthenticationService.svc/Logon"

    # Authentication
    $bodyParams = @{username = "$Global:apiUsername"; password = "$Global:apiPassword"} | ConvertTo-JSON

    # Execution
    try {
        $logonResult = Invoke-RestMethod -Uri $webServicesLogon -Method POST -ContentType "application/json" -Body $bodyParams -ErrorVariable logonResultErr
        Return $logonResult.CyberArkLogonResult
    }
    catch {
        Write-Host "StatusCode: " $_.Exception.Response.StatusCode.value__
        Write-Host "StatusDescription: " $_.Exception.Response.StatusDescription
        Write-Host "Response: " $_.Exception.Message
        Return $false
    }
}

function PASREST-GetAccount ([string]$Authorization, [string]$Keywords, [string]$Safe) {

    # Declaration
    $webServicesGA = "$Global:baseURL/PasswordVault/WebServices/PIMServices.svc/Accounts?Keywords=$Keywords&Safe=$Safe"

    # Authorization
    $headerParams = @{}
    $headerParams.Add("Authorization",$Authorization)

    # Execution
    try {
        $getAccountResult = Invoke-RestMethod -Uri $webServicesGA -Method GET -ContentType "application/json" -Headers $headerParams -ErrorVariable getAccountResultErr
        return $getAccountResult
    }
    catch {
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
        Write-Host "Response:" $_.Exception.Message
        return $false
    }
}

function PASREST-AddAccount ([string]$Authorization,[string]$ObjectName,[string]$Safe,[string]$PlatformID,[string]$Address,[string]$Username,[string]$Password,[boolean]$DisableAutoMgmt,[string]$DisableAutoMgmtReason) {

    # Declaration
    $webServicesAddAccount = "$Global:baseURL/PasswordVault/WebServices/PIMServices.svc/Account"

    # Authorization
    $headerParams = @{}
    $headerParams.Add("Authorization",$Authorization)
    $bodyParams = @{account = @{safe = $Safe; platformID = $PlatformID; address = $Address; accountName = $ObjectName; password = $Password; username = $Username; disableAutoMgmt = $DisableAutoMgmt; disableAutoMgmtReason = $DisableAutoMgmtReason}} | ConvertTo-JSON -Depth 2

    # Execution
    try {
        $addAccountResult = Invoke-RestMethod -Uri $webServicesAddAccount -Method POST -ContentType "application/json" -Header $headerParams -Body $bodyParams -ErrorVariable addAccountResultErr
        return $addAccountResult
    }
    catch {
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
        Write-Host "Response:" $_.Exception.Message
        return $false
    }
}


## DISABLE SSL VERIFICATION (THIS IS FOR DEV ONLY!)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

## SPLASH SCREEN
Write-Host "Welcome to Password Upload Utility v2" -ForegroundColor "Yellow"
Write-Host "=====================================" -ForegroundColor "Yellow"
Write-Host " "

## USER INPUT
$Global:baseURL = Read-Host "Please enter your PVWA address (https://pvwa.cyberark.local)"
$Global:apiUsername = Read-Host "Please enter your REST API Username (CyberArk/LDAP/RADIUS)"
$Global:apiPassword = Read-Host "Please enter ${apiUsername}'s password" -AsSecureString
$csvPath = OpenFile-Dialog($Env:CSIDL_DEFAULT_DOWNLOADS) 

## LOGON TO CYBERARK WEB SERVICES
$sessionID = PASREST-Logon
# Error Handling for Logon
if ($sessionID -eq $false) { Write-Host "[ERROR] There was an error logging into the Vault." -ForegroundColor "Red"; break }
else { Write-Host "[INFO] Logon completed successfully." -ForegroundColor "DarkYellow" }

## IMPORT CSV
$csvRows = Import-Csv -Path $csvPath
# Count the number of rows in the CSV
$rowCount = $csvRows.Count()
$counter = 1

## STEP THROUGH EACH CSV ROW
foreach ($row in $csvRows) {

    # DEFINE VARIABLES FOR EACH VALUE
    $objectName = $row.ObjectName
    $cpmUser    = $row.CPMUser
    $safe       = $row.Safe
    $folder     = "Root"
    $password   = $row.Password
    $deviceType = $row.DeviceType
    $platformID = $row.PlatformID
    $address    = $row.Address
    $username   = $row.Username
    $reset      = $row.ResetImmediately

    # CHECK FOR ACCOUNT ALREADY VAULTED
    $accountCheck = PASREST-GetAccount -Authorization $sessionID -Keywords [System.Web.HttpUtility]::UrlEncode($username) -Safe [System.Web.HttpUtility]::UrlEncode($safe)
    # If account is already vaulted, do not vault and break to next row.
    if ($accountCheck -ne $false) { Write-Host "[ERROR] The account ${username} at the address ${address} is already vaulted." -ForegroundColor "Red"; break }

    # ADD ACCOUNT TO VAULT
    $addResult = PASREST-AddAccount -Authorization $sessionID -ObjectName $objectName -Safe $safe -PlatformID $platformID -Address $address -Username $username -Password $password -DisableAutoMgmt $disableAutoMgmt -DisableAutoMgmtReason $disableAutoMgmtReason
    # If nothing is returned, there was an error and it will break to next row.
    if ($retVal -eq $false) { Write-Host "[ERROR] There was an error adding ${username}@${address} into the Vault." -ForegroundColor "Red"; break }
    else { $counter = $counter++; Write-Host "[INFO] [${counter}/${rowCount}] Added ${username}@${address} successfully." -ForegroundColor "DarkYellow" }
}

Write-Host " "
Write-Host "=====================================" -ForegroundColor "Yellow"
Write-Host "Vaulted ${counter} out of ${rowCount} accounts successfully."