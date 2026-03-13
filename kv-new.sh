#!/bin/bash

# Color codes for better visibility
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Azure Key Vault Secret Updater ===${NC}\n"

# Check if az CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI (az) is not installed!${NC}"
    exit 1
fi

# Ask for Key Vault name
echo -e "${YELLOW}Enter your Key Vault name:${NC}"
read keyvault_name

if [ -z "$keyvault_name" ]; then
    echo -e "${RED}Error: Key Vault name is required!${NC}"
    exit 1
fi

# Ask for input file with secret names
echo -e "${YELLOW}Enter the path to your kv.txt file (containing secret names):${NC}"
read input_file

if [ -z "$input_file" ]; then
    input_file="kv.txt"
fi

if [ ! -f "$input_file" ]; then
    echo -e "${RED}Error: File '$input_file' not found!${NC}"
    exit 1
fi

# Read secret names from file
echo -e "\n${GREEN}Reading secret names from $input_file...${NC}\n"

# Process each line in the file
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Extract secret name (handle different formats)
    # Format 1: secret_name: "value"
    # Format 2: secret_name
    secret_name=$(echo "$line" | sed -E 's/^[[:space:]]*([^:]+):.*/\1/' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    if [ -z "$secret_name" ]; then
        continue
    fi
    
    # Get current value from Key Vault
    echo -e "${BLUE}Secret: ${secret_name}${NC}"
    current_value=$(az keyvault secret show --vault-name "$keyvault_name" --name "$secret_name" --query "value" -o tsv 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "Current value: ${current_value:0:20}..." # Show first 20 chars for security
    else
        echo -e "${YELLOW}(Secret not found in Key Vault - will create new)${NC}"
        current_value=""
    fi
    
    echo -n "New value (press Enter to skip): "
    read -s new_value
    echo ""
    
    if [ -n "$new_value" ]; then
        # Update the secret in Key Vault
        az keyvault secret set --vault-name "$keyvault_name" --name "$secret_name" --value "$new_value" > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Updated successfully${NC}\n"
        else
            echo -e "${RED}✗ Failed to update${NC}\n"
        fi
    else
        echo -e "${YELLOW}⊘ Skipped${NC}\n"
    fi
    
done < "$input_file"

echo -e "${GREEN}Done!${NC}"