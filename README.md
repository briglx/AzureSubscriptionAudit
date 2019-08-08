# AzureSubscriptionAudit
Unofficial collection of scripts to audit an Azure subscription

# Usage

The `Add-SubscriptionRoleAssignmentRecord` script will iterate through all subscriptions the user has access to.

It will attempt to get the Role Assignments for that subscription including every resource the user has visibility to in the subscription.

The Role Assignment is then published to an Azure Table Storage Account.

The PowerBI Template has reports that pull from the Table.

```powershell
# Attempt to login
try {
    $null = Get-AzSubscription
}
catch {
    if ([string]::IsNullOrEmpty($env:AZURE_TENANT_ID) ){
        Connect-AzAccount
    } else {
        Connect-AzAccount -TenantId $env:AZURE_TENANT_ID
    }
}

# Get Metric Table
$azStorageContext = Get-AzContext "<Name of Subscription where Metric table lives>"
$resourceGroupName = '<metricTableResourceGroup>'
$storageAccountName = '<metricTableStorageAccountName>'
# Get Storage Table
$tableName = 'MetricsSubscriptionAccessAssignment'

. "./AzureAuditSubscription.ps1"

$metricTable = Get-MetricTable -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -MetricTableName $tableName -Context $azStorageContext 

Add-SubscriptionRoleAssignmentRecord -MetricTable $metricTable

```


# List Access

You can list the role assignments for a specified user, subscription, resource group, resource and classic resources.

## List Specific User

```
Get-AzRoleAssignment -SignInName isabella@example.com -ExpandPrincipalGroups | FL DisplayName, RoleDefinitionName, Scope
```

## List Role Assignment for Subscription Resource Group

```
Get-AzRoleAssignment -ResourceGroupName <resource_group_name>
```

## List Azure AD Applications

```
Get-AzADApplication
```

## List Service Principals for an application

```
 Get-AzADApplication -ObjectId 39e64ec6-569b-4030-8e1c-c3c519a05d69 | Get-AzADServicePrincipal
 ```


# References
- Manage Access using RBAC and Powershell https://docs.microsoft.com/en-us/azure/role-based-access-control/role-assignments-powershell
- Az.Resources https://docs.microsoft.com/en-us/powershell/module/az.resources/?view=azps-2.5.0#resources