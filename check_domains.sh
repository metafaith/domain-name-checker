#!/bin/bash

# Function to check a single domain
check_domain() {
    local domain=$1
    # Print the domain name, padded to 30 characters for clean formatting
    printf "%-30s " "$domain"

    # 1. Fast/Stealth Check: Look for NS records using dig
    local ns_records
    ns_records=$(dig +short NS "$domain" | tr '\n' ' ' | sed 's/ *$//')

    if [ -n "$ns_records" ]; then
        # If NS records exist, it's definitely registered.
        echo -e "[\033[0;31mREGISTERED\033[0m] NS: $ns_records"
    else
        # 2. Fallback Check: If no NS records, it might be parked or available.
        local whois_output
        whois_output=$(whois "$domain" 2>/dev/null)

        # Check for common "available" phrases across different TLD registries
        if echo "$whois_output" | grep -iqE 'no match|not found|no entries found|domain not found|available for registration|no data found'; then
            echo -e "[\033[0;32mAVAILABLE\033[0m]  Ready to register!"
        else
            echo -e "[\033[0;31mREGISTERED\033[0m] No active NS (Parked/Inactive)."
        fi
    fi
}

# Input validation
if [ -z "$1" ]; then
    echo "Error: No input provided."
    echo "Usage: $0 <domain.com> OR $0 <file_with_domains.txt>"
    exit 1
fi

# Check if the argument is a file
if [ -f "$1" ]; then
    echo "Scanning list from file: $1..."
    echo "---------------------------------------------------"
    # Read line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines or lines starting with #
        [[ -z "$line" || "$line" == \#* ]] && continue
        
        # Remove any stray whitespace/carriage returns
        clean_domain=$(echo "$line" | tr -d '[:space:]')
        check_domain "$clean_domain"
    done < "$1"
else
    # Treat the argument as a single domain
    echo "---------------------------------------------------"
    check_domain "$1"
fi
echo "---------------------------------------------------"
