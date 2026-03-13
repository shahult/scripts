#!/bin/bash

# Color codes for better visibility
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Key-Value Updater ===${NC}\n"

# Ask for input file
echo -e "${YELLOW}Enter the path to your input file (or press Enter for stdin):${NC}"
read input_file

# Read input
if [ -z "$input_file" ]; then
    echo -e "${YELLOW}Paste your key-value pairs (Ctrl+D when done):${NC}"
    content=$(cat)
else
    if [ ! -f "$input_file" ]; then
        echo "Error: File not found!"
        exit 1
    fi
    content=$(cat "$input_file")
fi

# Extract keys
keys=$(echo "$content" | grep -oP '^\s*\K[^:]+(?=:)' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

echo -e "\n${GREEN}Found the following keys:${NC}"
echo "$keys" | nl

echo -e "\n${YELLOW}Enter new values for each key:${NC}\n"

# Create updated content
updated_content="$content"

while IFS= read -r key; do
    # Get current value
    current_value=$(echo "$content" | grep "^[[:space:]]*${key}:" | grep -oP ':\s*"\K[^"]*')
    
    echo -e "${BLUE}Key: ${key}${NC}"
    echo "Current value: \"$current_value\""
    echo -n "New value (press Enter to keep current): "
    read new_value
    
    if [ -n "$new_value" ]; then
        # Escape special characters for sed
        escaped_key=$(echo "$key" | sed 's/[]\/$*.^[]/\\&/g')
        escaped_new=$(echo "$new_value" | sed 's/[\/&]/\\&/g')
        
        # Update the value
        updated_content=$(echo "$updated_content" | sed "s/^\([[:space:]]*${escaped_key}:[[:space:]]*\)\"[^\"]*\"/\1\"${escaped_new}\"/")
        echo -e "${GREEN}✓ Updated${NC}\n"
    else
        echo -e "${YELLOW}⊘ Kept original value${NC}\n"
    fi
done <<< "$keys"

# Ask for output method
echo -e "${YELLOW}How would you like to save the result?${NC}"
echo "1) Display on screen"
echo "2) Save to file"
echo "3) Overwrite original file"
read -p "Choose (1-3): " choice

case $choice in
    1)
        echo -e "\n${GREEN}=== Updated Content ===${NC}"
        echo "$updated_content"
        ;;
    2)
        read -p "Enter output filename: " output_file
        echo "$updated_content" > "$output_file"
        echo -e "${GREEN}✓ Saved to $output_file${NC}"
        ;;
    3)
        if [ -n "$input_file" ]; then
            echo "$updated_content" > "$input_file"
            echo -e "${GREEN}✓ Overwritten $input_file${NC}"
        else
            echo -e "${YELLOW}No input file to overwrite. Displaying content:${NC}"
            echo "$updated_content"
        fi
        ;;
    *)
        echo "Invalid choice. Displaying content:"
        echo "$updated_content"
        ;;
esac

echo -e "\n${GREEN}Done!${NC}"