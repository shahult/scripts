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

# Test access to Key Vault
echo -e "\n${YELLOW}Testing access to Key Vault...${NC}"
az keyvault secret list --vault-name "$keyvault_name" --query "[0].name" -o tsv > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Cannot access Key Vault '$keyvault_name'${NC}"
    echo -e "${YELLOW}Please check:${NC}"
    echo "  1. Key Vault name is correct"
    echo "  2. You're logged in: az login"
    echo "  3. You have 'Get' and 'Set' permissions for secrets"
    echo "  4. Try: az account show (to verify logged in account)"
    exit 1
fi

echo -e "${GREEN}✓ Key Vault access confirmed${NC}"

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
    
    # Try to get the secret value with better error handling
    current_value=$(az keyvault secret show --vault-name "$keyvault_name" --name "$secret_name" --query "value" -o tsv 2>&1)
    get_status=$?
    
    if [ $get_status -eq 0 ] && [ -n "$current_value" ]; then
        # Check if value is too long to display safely
        value_length=${#current_value}
        if [ $value_length -gt 50 ]; then
            echo "Current value: ${current_value:0:30}... (${value_length} chars total)"
        else
            echo "Current value: $current_value"
        fi
    else
        if echo "$current_value" | grep -q "not found"; then
            echo -e "${YELLOW}(Secret not found in Key Vault - will create new)${NC}"
        else
            echo -e "${RED}Error reading secret: $current_value${NC}"
            echo -e "${YELLOW}Will attempt to create/update anyway${NC}"
        fi
        current_value=""
    fi
    
    echo -n "New value (press Enter to skip): "
    read -s new_value </dev/tty
    echo ""
    
    if [ -n "$new_value" ]; then
        # Update the secret in Key Vault
        echo -e "${YELLOW}Updating secret...${NC}"
        update_output=$(az keyvault secret set --vault-name "$keyvault_name" --name "$secret_name" --value "$new_value" 2>&1)
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Updated successfully${NC}\n"
        else
            echo -e "${RED}✗ Failed to update${NC}"
            echo -e "${RED}Error: $update_output${NC}\n"
        fi
    else
        echo -e "${YELLOW}⊘ Skipped${NC}\n"
    fi
    
done < "$input_file"

echo -e "${GREEN}Done!${NC}"