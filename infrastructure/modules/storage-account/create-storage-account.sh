#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status

#Variables
resourceGroupName="crud-rg"
storageAccountName="crudstoragetf"
containerName="tfstate"
location="WestEurope"
sku="Standard_LRS"
subscriptionName=$(az account show --query name --output tsv)

# Create resource group
echo "Checking if [$resourceGroupName] resource group actually exists in the [$subscriptionName] subscription..."
if ! az group show --name "$resourceGroupName" &>/dev/null; then
    echo "No [$resourceGroupName] resource group actually exists in the [$subscriptionName] subscription"
    echo "Creating [$resourceGroupName] resource group in the [$subscriptionName] subscription..."

    # Create the resource group
    az group create \
        --name $resourceGroupName \
        --location $location 1>/dev/null

    if [[ $? == 0 ]]; then
        echo "[$resourceGroupName] resource group successfully created in the [$subscriptionName] subscription"
    else
        echo "Failed to create [$resourceGroupName] resource group in the [$subscriptionName] subscription"
        exit
    fi
else
    echo "[$resourceGroupName] resource group already exists in the [$subscriptionName] subscription"
fi

# Create storage account
echo "Checking if [$storageAccountName] storage account actually exists in the [$subscriptionName] subscription..."
if ! az storage account show --name "$storageAccountName" --resource-group "$resourceGroupName" &>/dev/null; then
    echo "No [$storageAccountName] storage account actually exists in the [$subscriptionName] subscription"
    echo "Creating [$storageAccountName] storage account in the [$subscriptionName] subscription..."

    az storage account create \
        --resource-group $resourceGroupName \
        --name $storageAccountName \
        --sku $sku \
        --encryption-services blob 1>/dev/null

    # Create the storage account
    if  [[ $? == 0 ]]; then
        echo "[$storageAccountName] storage account successfully created in the [$subscriptionName] subscription"
    else
        echo "Failed to create [$storageAccountName] storage account in the [$subscriptionName] subscription"
        exit
    fi
else
    echo "[$storageAccountName] storage account already exists in the [$subscriptionName] subscription"
fi

# Get storage account key
echo "Retrieving the primary key of the [$storageAccountName] storage account..."
storageAccountKey=$(az storage account keys list --resource-group $resourceGroupName --account-name $storageAccountName --query [0].value -o tsv)

if [[ -n $storageAccountKey ]]; then
    echo "Primary key of the [$storageAccountName] storage account successfully retrieved"
else
    echo "Failed to retrieve the primary key of the [$storageAccountName] storage account"
    exit
fi

# Create blob container
echo "Checking if [$containerName] container actually exists in the [$storageAccountName] storage account..."

if ! az storage container show --name "$containerName" --account-name "$storageAccountName" --account-key "$storageAccountKey" &>/dev/null; then
    echo "No [$containerName] container actually exists in the [$storageAccountName] storage account"
    echo "Creating [$containerName] container in the [$storageAccountName] storage account..."

    # Create the container
    az storage container create \
        --name $containerName \
        --account-name $storageAccountName \
        --account-key $storageAccountKey 1>/dev/null

    if  [[ $? == 0 ]]; then
        echo "[$containerName] container successfully created in the [$storageAccountName] storage account"
    else
        echo "Failed to create [$containerName] container in the [$storageAccountName] storage account"
        exit
    fi
else
    echo "[$containerName] container already exists in the [$storageAccountName] storage account"
fi

# Print data
echo "----------------------------------------------------------------------------------------------"
echo "storageAccountName: $storageAccountName"
echo "containerName: $containerName"
echo "access_key: $storageAccountKey"
