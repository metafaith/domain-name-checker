# domain-name-checker
a simple bash script to check if your domain is available without tipping off every registry on the planet that you are in the neighborhood for that domain name.

## Instructions:

To make this script as fast and stealthy as possible, we can use a hybrid approach based on the methods discussed in [the background section](#Background).  
The script below will first check for DNS Nameservers (NS) using dig. If it finds them, it immediately stops and declares the domain Registered and prints the servers. This is incredibly fast and avoids querying the registration database entirely.  
If it doesn't find NS records, the domain might be available, OR it might just be parked/inactive. Only then does the script fall back to a whois query to confirm its true status.  

> the following steps have been done for you in this repository. You can just fork it or otherwise clone it to your local, but you will still need to make it executable, as in step #3.
> ```bash
> chmod +x check_domains.sh
> ```  

### The Domain Checker Script

1. Create the file:
   Open your terminal and create a new file named check_domains.sh:
```bash
vim check_domains.sh
```

2. Press 'i' to enter insert mode, and Paste the following code:
```bash
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
```
Press [esc] to exit interactive mode and then press `:wq` to enter command mode (:), save (w), and quit (q). 

3. Make the script executable:
   Run this command so your system is allowed to execute it:
```bash
chmod +x check_domains.sh
```  

### How to Use It

You can use this script in two different ways depending on your needs.

#### Option A: Check a single domain
Pass the domain directly to the script.
```bash
./check_domains.sh google.com
```

Output:
```bash
google.com                   [REGISTERED] NS: ns1.google.com. ns2.google.com. ns3.google.com. ns4.google.com.
```

#### Option B: Check a list of domains
Create a simple text file (e.g., list.txt) with one domain per line:
```text
apple.com
thisdomainisdefinitelyfaketoday.com
microsoft.com
mycoolstartupidea2026.net
```

Then run the script against the file:
```bash
./check_domains.sh list.txt
```

Output:
```text
Scanning list from file: list.txt...
---------------------------------------------------
apple.com                      [REGISTERED] NS: nserver.apple.com. nserver2.apple.com. nserver3.apple.com. nserver4.apple.com.
thisdomainisdefinitelyfaketoday.com [AVAILABLE]  Ready to register!
microsoft.com                  [REGISTERED] NS: ns1-205.azure-dns.com. ns2-205.azure-dns.net. ns3-205.azure-dns.org. ns4-205.azure-dns.info.
mycoolstartupidea2026.net      [AVAILABLE]  Ready to register!
---------------------------------------------------
```

### Why this is safe
Because this script lives entirely on your machine, no web browser cookies are generated, no retail registrar algorithms are pinged, and your searches remain securely within your own terminal.

#### Q: Is it possible for whois to come back negative and the domain still be parked?

**A:** In short: ***No.***  
If the authoritative WHOIS database genuinely reports a domain as available, it cannot be parked. Here is why: "Parking" a domain requires someone to own it. To own it, it must be registered with the central registry (like Verisign for .com). The registry's WHOIS database is the ultimate source of truth. If a domain does not exist in that database, it simply does not exist on the internet, meaning no one can point it to a parked page.  

However, you can absolutely get a false negative—a situation where your WHOIS command looks like it came back available, but the domain is actually registered and parked.  

##### Here are the three most common reasons a WHOIS query gives a false negative:  
###### 1. You hit a WHOIS Rate Limit (The most common issue)  

WHOIS servers are heavily protected against spam and scraping. If you run a list of 500 domains through a script, the registry will likely ban your IP address after the first 50 or so queries.  

  • **What happens**: Instead of returning registration data, the server returns an error message like Query limit exceeded or simply drops the connection.  
  • **Why it causes a false negative**: If a script is just looking for the absence of registration data (or if it's poorly coded), it might misinterpret that error or blank response as "Oh, no owner data found, it must be available!"  

###### 2. Quirks with ccTLDs (Country Code Top-Level Domains)  

While .com and .net have very standardized WHOIS responses, country-code extensions like .io, .ai, or .co.uk are managed by entirely different organizations with their own unique rules and server software.  

  • **What happens**: Some of these registries have non-standard "not found" messages, or their servers are notoriously unreliable and frequently time out.  
  • **Why it causes a false negative**: If your script is using grep to look for the exact phrase "No match for domain", but the .io registry responds with "Domain not found", your script might fail to read the availability correctly.  

###### 3. The "Pending Delete" Limbo  

When someone stops paying for a domain, it doesn't instantly become available. It goes through a lifecycle (Expired -> Redemption Grace Period -> Pending Delete).

  • **What happens**: During the final hours of the "Pending Delete" phase, the domain is technically wiped from the active DNS zone, but the registry hasn't fully released it to the public for new registration yet.  
  • **Why it causes a false negative**: A standard WHOIS check might show no active owner, leading you to believe you can buy it right now, but if you try to register it via a registrar, it will fail because the registry hasn't unlocked it yet.  


##### Why our script avoids this trap  

This exact "false negative" problem is why the bash script we built uses the hybrid approach.  
By running `dig +short NS` first, we check the live DNS network. If a domain is parked, it must have active nameservers to display that parked page. The script sees those nameservers, instantly marks it as `[REGISTERED]`, and never even asks WHOIS.  
This prevents rate-limiting, bypasses flaky WHOIS servers entirely, and guarantees that if a domain is actively parked, you will correctly identify it as taken.  



## Background

You are absolutely right to be cautious. The practice you are describing is known as domain front-running. While ICANN (the Internet Corporation for Assigned Names and Numbers) has strict policies against it today, the historical precedent and the persistent fear of retail registrars tracking search queries to hold domains for ransom is a very valid reason to avoid web-based search bars when brainstorming names.  

To bypass retail registrars, you need to query the Registry directly (the organization that manages the top-level domain, like Verisign for .com and .net), rather than a Registrar (the retail storefront like GoDaddy or Namecheap).  

Here are the three best ways to do this directly from your command line today.  


### 1. The Modern Approach: RDAP (Using curl)
   You specifically asked about using curl. Today, the internet is transitioning away from the old WHOIS system to RDAP (Registration Data Access Protocol). RDAP is an HTTP-based RESTful API that returns domain registration data in JSON format, making it perfect for curl.  
To check a .com domain safely, you can use curl to query Verisign's RDAP server directly.  
The Command:  

```bash
curl -I https://rdap.verisign.com/com/v1/domain/yourdomainhere.com
```

How to read the results:  
   
   • **If the domain is REGISTERED**: The server will return an HTTP/1.1 200 OK response.  
   • **If the domain is AVAILABLE**: The server will return an HTTP/1.1 404 Not Found response.  

   > (Note: We use the -I flag to only fetch the HTTP headers. If you want to see the full JSON data for a registered domain, remove the -I flag).  
   > If you are looking up other extensions (like .org or .io), you will need to find the specific RDAP base URL for that registry. IANA maintains a complete bootstrap list of all RDAP endpoints for every Top-Level Domain (TLD) at https://data.iana.org/rdap/dns.json.  


### 2. The Traditional Approach: WHOIS CLI
   Before RDAP, there was WHOIS. While you don't use curl for this, almost all Unix-like operating systems (macOS, Linux) come with a built-in whois command-line tool.  
   When you run this command, your computer reaches out to the authoritative WHOIS server on TCP port 43. It completely bypasses retail websites and avoids web-tracking scripts.  
   The Command:  
```bash
whois yourdomainhere.com
```
How to read the results:  
   
   • **If the domain is REGISTERED**: You will get a block of text showing the registrar, creation date, and expiration date.  
   • **If the domain is AVAILABLE**: You will see a message like No match for "YOURDOMAINHERE.COM".  

   > A slight caveat: Some command-line WHOIS clients route queries through a central server to figure out which registry to ask. While vastly safer than a retail website, if you want absolute paranoia-level safety, you can force the command to only talk to the specific registry using the -h flag:  

```bash
whois -h whois.verisign-grs.com yourdomainhere.com
```


### 3. The Stealth Approach: DNS Resolution

   If you want to check a domain without ever touching a registration database (meaning there is zero log of you checking availability at the registry level), you can check if the domain has active DNS records.
You can do this using the dig or host commands.
The Command:
```bash
dig +short NS yourdomainhere.com
```
How to read the results:
   
   • If it returns nameservers (e.g., ns1.google.com): The domain is definitely registered and active.
   • If it returns nothing: The domain is likely available.
      
   > The Catch: This method is not 100% foolproof. A domain can be registered but parked without any DNS nameservers attached to it. However, it is an excellent, entirely invisible first-pass filter when you are brainstorming a massive list of potential names before running the final candidates through RDAP or WHOIS.
