<#
.SYNOPSIS
	AzureAuditSubscription.ps1 - PowerShell scripts that contains functions related to auditing an Azure Subscription.
.DESCRIPTION
  	AzureAuditSubscription.ps1 - PowerShell scripts that contains functions related to auditing an Azure Subscription.ell Module that contains all functions related to manipulating Azure Storage Table rows/entities.
.NOTES
	This module depends on Az.Accounts, Az.Resources, AzTable PowerShell modules	
#>

function Get-MetricTable
{
    <#
    .SYNOPSIS
        Get the Metric Table to store records.
    .DESCRIPTION
        Get the Metric Table to store records.
    .PARAMETER ResourceGroupName
        The Name of the Resource Group of the Storage account for the metrics table
    .PARAMETER StorageAccountName
        The Name of the Storage account for the metrics table
    .PARAMETER MetricTableName
        The Name of the metrics table
    .PARAMETER Context
        The current metadata used to authenticate Azure Resource Manager request
    .EXAMPLE
        # Getting the metrics table
        $resourceGroupName = "myResourceGroup"
        $storageAccountName = "myStorageAccountName"
        $tableName = "table01"
        $storageContext = Get-AzContext
        $metricTable = Get-MetricTable -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -MetricTableName $tableName -Context $storageContext 
    #>
	[CmdletBinding()]
    param
	(
		[Parameter(Mandatory=$true)]
        $ResourceGroupName,
        
        [Parameter(Mandatory=$true)]
        $StorageAccountName,
        
        [Parameter(Mandatory=$true)]
        $MetricTableName,
        
        [Parameter(Mandatory=$true)]
		$Context
	)
   
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -DefaultProfile $context
    $storageContext = $storageAccount.Context
    $storageTable  = Get-AzStorageTable –Name $metricTableName –Context $storageContext
    $cloudTable = $storageTable.CloudTable

    return $cloudTable
}

function Convert-ObjectToHash($object){

    $hash = @{}

    $object.psobject.properties | ForEach-Object { 
        # Don't add null values
        if($null -ne $_.Value ){
            $hash[$_.Name] = $_.Value 
        }
    }

    return $hash
}

function Test-AzRoleAssignmentResourceType($resourceType){
    <#
    .SYNOPSIS
        Test the Role Assignment Resource Type.
    .DESCRIPTION
        Role assignment is only allowed on certain Resource Types. 
        Returns $true if the resource type can have assignments.
        Returns $false if the resource type can not have assignments.
    .PARAMETER ResourceType
        The Resource Type to check
    .EXAMPLE
        $isValidResourceType = Test-AzRoleAssignmentResourceType $resource.ResourceType 
    #>

    if ($resourceType -eq "Microsoft.Compute/virtualMachines/extensions"){
        return $false
    }

    if ($resourceType -eq "Microsoft.Sql/servers/databases"){
        return $false
    }

    return $true

}

function Add-SubscriptionRoleAssignmentRecord {
    <#
    .SYNOPSIS
        Adds Subscription Role Assignment record a Storage Table.
    .DESCRIPTION
        Adds Subscription Role Assignment record a Storage Table.
    .PARAMETER metricTable
        The utilization table to save records
    .EXAMPLE
        # Getting latest role assignments
        $resourceGroupName = "myResourceGroup"
        $storageAccountName = "myStorageAccountName"
        $tableName = "table01"
        $storageContext = Get-AzContext
        $metricTable = Get-MetricTable -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -MetricTableName $tableName -Context $storageContext 
        Add-SubscriptionRoleAssignmentRecord -MetricTable $metricTable
    #>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)]
        $metricTable
    )

    $contexts = Get-AzContext -ListAvailable

    foreach($context in $contexts){

        $curSubscription = $context.Subscription
        Set-AzContext -Context $context

        $timeNow = [DateTime]::UtcNow

        try{

            # Capture Subscription Assignments
            $assignments = Get-AzRoleAssignment -IncludeClassicAdministrators
       
            foreach ($assignment in $assignments){

                $row = new-object psobject
                $row | add-member NoteProperty "Month" $timeNow.ToString("yyyy-MM")
                $row | add-member NoteProperty "Subscription" $curSubscription.Id
                $row | add-member NoteProperty "SubscriptionName" $curSubscription.Name
                $row | add-member NoteProperty "AssignmentScope" $assignment.Scope
                $row | add-member NoteProperty "AssignmentName" $assignment.DisplayName
                $row | add-member NoteProperty "RoleDefinitionName" $assignment.RoleDefinitionName
                $row | add-member NoteProperty "RoleDefinitionId" $assignment.RoleDefinitionId
                $row | add-member NoteProperty "ObjectId" $assignment.ObjectId
                $row | add-member NoteProperty "ObjectType" $assignment.ObjectType

                # Table only allows hash tables
                $hash = Convert-ObjectToHash($row)

                $partitionKey = $timeNow | get-date -Format "yyyyMMddTHHmmZ" 
                $rowKey = $assignment.Scope + ";" + $assignment.DisplayName -replace '\s|\/|\@|\.', '_' 

                # Publish Row to Table Storage
                $null = Add-AzTableRow -table $metricTable -partitionKey $partitionKey -rowKey ($rowKey) -property $hash
            
            }
        }
        catch [System.Management.Automation.MethodInvocationException]{
            if(
                ($Error.Count -gt 0) -and 
                ($Error[0].Exception.InnerException) -and 
                ($Error[0].Exception.InnerException.RequestInformation) -and 
                ($Error[0].Exception.InnerException.RequestInformation.HttpStatusMessage) -and
                ($Error[0].Exception.InnerException.RequestInformation.HttpStatusMessage -eq 'Conflict')) {

                    # Skip, This Role assignment scope was already recorded

            }
            else {
                Write-Error "Unknown Error Adding Role Assignment to Table" 
                Write-Error  $_.Exception.Message
            }
        }
        catch{

            Write-Error "Unknown Error Adding Role Assignment to Table"
            Write-Error  $_.Exception.Message
        }

        # Capture Resource Assignments
        $resources = Get-AzResource -DefaultProfile $context
        $i = 1
        foreach($resource in $resources) {

            try{

                Write-Progress -Activity "Checking Role Assignment for $($resource.Name)" -Status "Resource $i of $($resources.Count)" -PercentComplete (($i / $resources.Count) * 100) 
                Write-Debug $resource.ResourceGroupName  $resource.Name  $resource.ResourceType

                if($resource.ResourceGroupName -and $resource.Name -and $resource.ResourceType -and (Test-AzRoleAssignmentResourceType $resource.ResourceType)){

                    $assignments = Get-AzRoleAssignment -ResourceGroupName $resource.ResourceGroupName -ResourceName $resource.Name -ResourceType $resource.ResourceType -IncludeClassicAdministrators -DefaultProfile $context

                    foreach ($assignment in $assignments){

                        $row = new-object psobject
                        $row | add-member NoteProperty "Month" $timeNow.ToString("yyyy-MM")
                        $row | add-member NoteProperty "Subscription" $curSubscription.Id
                        $row | add-member NoteProperty "SubscriptionName" $curSubscription.Name
                        $row | add-member NoteProperty "ResourceGroupName" $resource.ResourceGroupName
                        $row | add-member NoteProperty "ResourceId" $resource.ResourceId
                        $row | add-member NoteProperty "AssignmentScope" $assignment.Scope
                        $row | add-member NoteProperty "AssignmentName" $assignment.DisplayName
                        $row | add-member NoteProperty "RoleDefinitionName" $assignment.RoleDefinitionName
                        $row | add-member NoteProperty "RoleDefinitionId" $assignment.RoleDefinitionId
                        $row | add-member NoteProperty "ObjectId" $assignment.ObjectId
                        $row | add-member NoteProperty "ObjectType" $assignment.ObjectType

                        # Table only allows hash tables
                        $hash = Convert-ObjectToHash($row)

                        $partitionKey = $timeNow | get-date -Format "yyyyMMddTHHmmZ"
                        $rowKey = $assignment.Scope + ";" + $assignment.DisplayName -replace '\s|\/|\@|\.', '_' 

                        try{

                            # Publish Row to Table Storage
                            $null = Add-AzTableRow -table $metricTable -partitionKey $partitionKey -rowKey ($rowKey) -property $hash
                        
                        }
                        catch [System.Management.Automation.MethodInvocationException]{
                            
                            if(
                                ($Error.Count -gt 0) -and 
                                ($Error[0].Exception.InnerException) -and 
                                ($Error[0].Exception.InnerException.RequestInformation) -and 
                                ($Error[0].Exception.InnerException.RequestInformation.HttpStatusMessage) -and
                                ($Error[0].Exception.InnerException.RequestInformation.HttpStatusMessage -eq 'Conflict')) {

                                # Skip, This Role assignment scope was already recorded
                                
                            }
                            else {
                                Write-Error "Unknown Error Adding Resource Role Assignment to Table" 
                                Write-Error  $_.Exception.Message
                            }
                        
                        }
                        catch{
                            Write-Error "Unknown Error Adding Resource Role Assignment to Table" 
                            Write-Error  $_.Exception.Message
                        }
                    }
                }
                else {
                    
                    Write-Debug "Not a Valid Resource for Role Assignment" 
                    Write-Debug $resource.ResourceGroupName $resource.Name $resource.ResourceType
                }

                
            }
            catch{
                Write-Error "Unknown Error Getting Role Assignment" 
                Write-Error  $_.Exception.Message
            }

            $i++
        }
    }
}
