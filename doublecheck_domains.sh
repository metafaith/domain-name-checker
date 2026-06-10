#!/bin/bash

IANA_URL="https://data.iana.org/rdap/dns.json"
CACHE_FILE="/tmp/iana_rdap_bootstrap.json"

# Download the IANA bootstrap file once per session to avoid spamming IANA
if [ ! -f "$CACHE_FILE" ]; then
    echo "Downloading IANA RDAP bootstrap file..."
    curl -s "$IANA_URL" -o "$CACHE_FILE"
fi

# Function to dynamically extract the RDAP base URL using whatever parser is available
get_rdap_url() {
    local tld=$1
    local url=""

    if command -v jq >/dev/null 2>&1; then
        url=$(jq -r --arg tld "$tld" '.services[] | select(.[0][] | . == $tld) | .[1][0]' "$CACHE_FILE" 2>/dev/null)
    
    elif command -v python3 >/dev/null 2>&1; then
        # Heredoc passed into Python3
        url=$(python3 - "$CACHE_FILE" "$tld" << 'EOF'
import sys, json
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    for s in data.get('services', []):
        if sys.argv[2] in s[0]:
            print(s[1][0])
            sys.exit(0)
except Exception:
    pass
EOF
        )

    elif command -v node >/dev/null 2>&1; then
        # Inline script passed into Node
        url=$(node -e "
            try {
                const fs = require('fs');
                const data = JSON.parse(fs.readFileSync('$CACHE_FILE'));
                const match = data.services.find(s => s[0].includes('$tld'));
                if(match) console.log(match[1][0]);
            } catch(e) {}
        ")
    fi

    echo "$url"
}

# Function to check the domain
check_domain() {
    local domain=$1
    local tld="${domain##*.}"
    printf "%-35s " "$domain"

    # --- LAYER 1: THE STEALTH CHECK (DNS) ---
    local ns_records
    ns_records=$(dig +short NS "$domain" | tr '\n' ' ' | sed 's/ *$//')

    if [ -n "$ns_records" ]; then
        echo -e "[\033[0;31mREGISTERED\033[0m] (Active DNS)"
        return
    fi

    # --- LAYER 2: THE MODERN CHECK (RDAP) ---
    local rdap_base_url
    rdap_base_url=$(get_rdap_url "$tld")

    if [ -n "$rdap_base_url" ]; then
        # Format the final URL correctly (ensuring no double slashes before 'domain/')
        local rdap_url="${rdap_base_url%/}/domain/$domain"
        
        # Get just the HTTP status code
        local http_status
        http_status=$(curl -s -o /dev/null -w "%{http_code}" "$rdap_url")

        if [ "$http_status" == "200" ]; then
            echo -e "[\033[0;31mREGISTERED\033[0m] (RDAP Confirmed Parked/Inactive)"
            return
        elif [ "$http_status" == "404" ]; then
            echo -e "[\033[0;32mAVAILABLE\033[0m]  (RDAP Confirmed!)"
            return
        elif [ "$http_status" == "429" ]; then
            printf "[\033[0;33mRDAP RATE LIMITED\033[0m] Falling back to WHOIS... "
        else
            printf "[\033[0;33mRDAP ERR %s\033[0m] Falling back to WHOIS... " "$http_status"
        fi
    else
        printf "[\033[0;33mNO RDAP PARSER/URL\033[0m] Falling back to WHOIS... "
    fi

    # --- LAYER 3: THE FALLBACK CHECK (WHOIS) ---
    local whois_output
    whois_output=$(whois "$domain" 2>/dev/null)

    if echo "$whois_output" | grep -iqE 'no match|not found|no entries found|domain not found|available for registration|no data found'; then
        echo -e "[\033[0;32mAVAILABLE\033[0m]"
    else
        # If it doesn't explicitly say it's available, assume it's registered
        echo -e "[\033[0;31mREGISTERED\033[0m] (WHOIS Confirmed Parked/Inactive)"
    fi
}

# --- MAIN EXECUTION ---
if [ -z "$1" ]; then
    echo "Usage: $0 <domain.com> OR $0 <file_with_domains.txt>"
    exit 1
fi

if [ -f "$1" ]; then
    echo "Scanning list from file: $1..."
    echo "------------------------------------------------------------"
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        clean_domain=$(echo "$line" | tr -d '[:space:]')
        check_domain "$clean_domain"
    done < "$1"
else
    echo "------------------------------------------------------------"
    check_domain "$1"
fi
echo "------------------------------------------------------------"
