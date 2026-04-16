#!/bin/bash

# Colors
G="\e[32m"
B="\e[34m"
R="\e[31m"
Y="\e[33m"
N="\e[0m"

# Default Values
VERBOSE=""
WORDLIST="wordlist.txt"
RATE="1000"
THREADS="50" # Default rate limit for DNS/HTTP

usage() {
    echo -e "${Y}Usage: $0 -d <domain> [-v] [-w <wordlist>] [-m <packet_rate>] [-t <threads>]${N}"
    echo -e "  -t : Sets threads for puredns/httpx (default 50)"
    echo -e "  -m : Sets --min-rate for naabu/nmap (default 1000)"
    exit 1
}

while getopts "d:vw:m:t:" opt; do
    case ${opt} in
        d ) DOMAIN=$OPTARG ;;
        v ) VERBOSE="-v" ;;
        w ) WORDLIST=$OPTARG ;;
        m ) RATE=$OPTARG ;;
        t ) THREADS=$OPTARG ;;
        * ) usage ;;
    esac
done

if [ -z "$DOMAIN" ]; then usage; fi

echo -e "${B}[*] Target: $DOMAIN | Thread Limit: $THREADS | Packet Rate: $RATE${N}"

# Phase 1: Passive
echo -e "${G}[+] Phase 1: Passive DNS Discovery...${N}"
subfinder -d "$DOMAIN" $VERBOSE -o passive-subdomains.txt > /dev/null 2>&1
echo -e "${Y}[!] Found $(wc -l < passive-subdomains.txt) passive subdomains.${N}"

# Phase 2: DNS Resolution
echo -e "${G}[+] Phase 2: DNS Resolution (Rate: $THREADS threads)...${N}"
# -n flag in puredns limits parallel tasks
cat passive-subdomains.txt | puredns resolve --rate-limit "$THREADS" | tee resolved.txt > /dev/null
echo -e "${Y}[!] $(wc -l < resolved.txt) subdomains resolved.${N}"

# Phase 3: Active Discovery
echo -e "${G}[+] Phase 3: Active Discovery...${N}"
if [ -f "$WORDLIST" ]; then
    puredns bruteforce "$WORDLIST" "$DOMAIN" --rate-limit "$THREADS" -w bruteforce-results.txt > /dev/null
    echo -e "${Y}[!] Bruteforce found $(wc -l < bruteforce-results.txt) subdomains.${N}"
else
    echo -e "${R}[-] Wordlist not found, skipping.${N}"
    touch bruteforce-results.txt
fi

echo -e "${B}[*] Running Alterx permutations...${N}"
cat passive-subdomains.txt | alterx -silent | puredns resolve --rate-limit "$THREADS" | tee permutations.txt > /dev/null

# Phase 4: Web Probing
echo -e "${G}[+] Phase 4: Combining & Web Probing...${N}"
cat resolved.txt bruteforce-results.txt permutations.txt | sort -u > all-live-subs.txt
# -t in httpx sets thread count
httpx -l all-live-subs.txt -title -status-code -ip -cname -tech-detect -t "$THREADS" -o metadata.txt -silent
echo -e "${Y}[!] Total Unique: $(wc -l < all-live-subs.txt). Metadata saved.${N}"

# Phase 5: Network Exposure
echo -e "${G}[+] Phase 5: Network Service Discovery (Rate: $RATE)...${N}"
PORTS="21,22,3306,5432,27017,6379,9200"
naabu -l all-live-subs.txt -p "$PORTS" -rate "$RATE" -o services.txt -silent
nmap -sV -p- --min-rate "$RATE" "$DOMAIN" -oN nmap_report.txt > /dev/null

# Final Processing
python3 formatter.py
echo -e "${B}[*] Recon Complete. Check recon_report.md${N}"
