#
# ProvisionOnlineInstance.ps1
#
[CmdletBinding()]
param(
[string]$ApiUrl,
[string]$Username,
[string]$Password,
[string]$InstanceName,
[string]$DomainName,
[string]$FriendlyName,
[string]$Purpose,
[string]$TargetReleaseName = 'Dynamics 365, version 9.0',
[string[]]$TemplateNames,
[string]$LanguageId,
[string]$PreferredCulture,
[string]$CurrencyCode,
[string]$CurrencyName,
[int]$CurrencyPrecision,
[string]$CurrencySymbol,
[string]$SecurityGroupId,
[string]$SecurityGroupName,
[bool]$WaitForCompletion = $false,
[int]$SleepDuration = 3,
[string]$PSModulePath
)

$ErrorActionPreference = "Stop"

Write-Verbose 'Entering ResetOnlineInstance.ps1'

#Parameters
Write-Verbose "ApiUrl = $ApiUrl"
Write-Verbose "Username = $Username"
Write-Verbose "InstanceName = $InstanceName"
Write-Verbose "DomainName = $DomainName"
Write-Verbose "FriendlyName = $FriendlyName"
Write-Verbose "Purpose = $Purpose"
Write-Verbose "PreferredCulture = $PreferredCulture"
Write-Verbose "TargetReleaseName = $TargetReleaseName"
Write-Verbose "TemplateNames = $TemplateNames"
Write-Verbose "LanguageId = $LanguageId"
Write-Verbose "CurrencyCode = $CurrencyCode"
Write-Verbose "CurrencyName = $CurrencyName"
Write-Verbose "CurrencyPrecision = $CurrencyPrecision"
Write-Verbose "CurrencySymbol = $CurrencySymbol"
Write-Verbose "SecurityGroupId = $SecurityGroupId"
Write-Verbose "SecurityGroupName = $SecurityGroupName"
Write-Verbose "WaitForCompletion = $WaitForCompletion"
Write-Verbose "SleepDuration = $SleepDuration"
Write-Verbose "PSModulePath = $PSModulePath"

#Script Location
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
Write-Verbose "Script Path: $scriptPath"

#Set Security Protocol
& "$scriptPath\SetTlsVersion.ps1"

#Load Online Management Module
$xrmOnlineModule = $scriptPath + "\Microsoft.Xrm.OnlineManagementAPI.dll"

if ($PSModulePath)
{
	$xrmOnlineModule = $PSModulePath + "\Microsoft.Xrm.OnlineManagementAPI.dll"
}

Write-Verbose "Importing Online Management Module: $xrmOnlineModule" 
Import-Module $xrmOnlineModule
Write-Verbose "Imported Online Management Module"

#Create Credentials
$SecPassword = ConvertTo-SecureString $Password -AsPlainText -Force
$Cred = New-Object System.Management.Automation.PSCredential ($Username, $SecPassword)

."$scriptPath\OnlineInstanceFunctions.ps1"

$instance = Get-XrmInstanceByName -ApiUrl $ApiUrl -Cred $Cred -InstanceName $InstanceName

if ($instance -eq $null)
{
    throw "$InstanceName not found"
}

Write-Host "Resetting instance $InstanceName $($instance.Id)"

$instance
 
$InstanceInfoParams = @{
	BaseLanguage = $LanguageId
	DomainName = $DomainName
	FriendlyName = $FriendlyName
	TargetReleaseName = $TargetReleaseName
	Purpose = $Purpose
	TemplateList = $TemplateNames
}

if ($PreferredCulture -ne 0)
{
	$InstanceInfoParams.PreferredCulture = $PreferredCulture
}
if ($CurrencyCode -ne '')
{
	$InstanceInfoParams.CurrencyCode = $CurrencyCode
}
if ($CurrencyName -ne '')
{
	$InstanceInfoParams.CurrencyName = $CurrencyName
}
if ($CurrencyPrecision -ne 0)
{
	$InstanceInfoParams.CurrencyPrecision = $CurrencyPrecision
}
if ($CurrencySymbol -ne '')
{
	$InstanceInfoParams.CurrencySymbol = $CurrencySymbol
}

if ($SecurityGroupName -ne '')
{
	Write-Verbose "Importing Module AzureAD" 
	Import-Module AzureAD
	Write-Verbose "Imported Module AzureAD" 
	
	$group = Get-AzureADGroup -Filter "DisplayName eq '$SecurityGroupName'"

	if ($group -ne $null)
	{
		$SecurityGroupId = $group.ObjectId
	}
	if ($group -eq $null)
	{
		throw "$SecurityGroupName not found"
	}
}

if ($SecurityGroupId -ne '')
{
	$InstanceInfoParams.SecurityGroupId = $SecurityGroupId
}

$instanceInfo = New-CrmInstanceResetRequestInfo @InstanceInfoParams

$operation = Reset-CrmInstance  -ApiUrl $ApiUrl -Credential $Cred -TargetInstanceIdToReset $instance.Id -ResetInstanceRequestDetails $instanceInfo

$OperationId = $operation.OperationId
$OperationStatus = $operation.Status

Write-Host "Reset started OperationId: $OperationId - Status: $OperationStatus" -ForegroundColor Green

if ($operation.Errors.Count -gt 0)
{
    $errorMessage = $operation.Errors[0].Description
    throw "Errors encountered : $errorMessage"
}

if ($WaitForCompletion -and ($OperationStatus -ne "Succeeded"))
{
	Write-Host "Waiting for AsyncOperation to complete"

	$status = Wait-XrmOperation -ApiUrl $ApiUrl -Cred $Cred -operationId $operation.OperationId

	$status

	if ($status.Status -ne "Succeeded")
	{
		throw "Operation status: $status.Status"
	}
}
else
{
	Write-Verbose "Skipped waiting for Async Operation"
}

if ($WaitForCompletion)
{
	#Sometimes reset is created but the API still returns old id
	#Added this delay to give chance for operation to progress.

	Write-Host "Starting Sleep for 60 seconds"

	Start-Sleep -Seconds 60
	
	#$provisioning = $true
	#while ($provisioning)
	#{
	#	Write-Verbose "Starting Sleep for $SleepDuration seconds"
		
	#	Start-Sleep -Seconds $SleepDuration

	#	Write-Verbose "Attempting to retrieve instance: $DomainName"

	#	$newInstance = Get-XrmInstanceByName -ApiUrl $ApiUrl -Cred $Cred -InstanceName $DomainName

	#	if ($newInstance)
 #       {
 #           $State = $newInstance.State

	#	    Write-Host "Instance Id: $($newInstance.Id) - State: $State"

	#	    if (($State -eq "Ready") -and ($newInstance.Id -ne $instance.Id))
	#	    {
	#		    $provisioning = $false
	#	    }
 #       }
 #       else
 #       {
 #           Write-Host "Instance: $DomainName not found"
 #       }
	#}
}

Write-Verbose 'Leaving ResetOnlineInstance.ps1'
