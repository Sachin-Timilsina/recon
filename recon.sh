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

usage() {
    echo -e "${Y}Usage: $0 -d <domain> [-v] [-w <wordlist>] [-m <rate>]${N}"
    exit 1
}

while getopts "d:vw:m:" opt; do
    case ${opt} in
        d ) DOMAIN=$OPTARG ;;
        v ) VERBOSE="-v" ;;
        w ) WORDLIST=$OPTARG ;;
        m ) RATE=$OPTARG ;;
        * ) usage ;;
    esac
done

if [ -z "$DOMAIN" ]; then usage; fi

# Create Directory Structure
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_DIR="recon_${DOMAIN}_${TIMESTAMP}"
mkdir -p "$OUT_DIR"/{passive,active,web,network,reports}

echo -e "${B}[*] Target: $DOMAIN${N}"
echo -e "${B}[*] Results will be saved in: $OUT_DIR${N}"

# Phase 1: Passive Discovery
echo -e "${G}[+] Phase 1: Passive DNS Discovery...${N}"
subfinder -d "$DOMAIN" $VERBOSE -o "$OUT_DIR/passive/passive-subdomain.txt" > /dev/null 2>&1
P1_COUNT=$(wc -l < "$OUT_DIR/passive/passive-subdomain.txt" 2>/dev/null || echo 0)
echo -e "${Y}[!] Found $P1_COUNT passive subdomains.${N}"

# Phase 2: DNS Resolution
echo -e "${G}[+] Phase 2: DNS Resolution...${N}"
cat "$OUT_DIR/passive/passive-subdomain.txt" | puredns resolve | tee "$OUT_DIR/active/resolved.txt" > /dev/null
P2_COUNT=$(wc -l < "$OUT_DIR/active/resolved.txt" 2>/dev/null || echo 0)
echo -e "${Y}[!] $P2_COUNT subdomains resolved.${N}"

# Phase 3: Active Discovery
echo -e "${G}[+] Phase 3: Active Discovery...${N}"
if [ -f "$WORDLIST" ]; then
    puredns bruteforce "$WORDLIST" "$DOMAIN" -w "$OUT_DIR/active/bruteforce-results.txt" > /dev/null
    BRUTE_COUNT=$(wc -l < "$OUT_DIR/active/bruteforce-results.txt" 2>/dev/null || echo 0)
    echo -e "${Y}[!] Bruteforce found $BRUTE_COUNT new subdomains.${N}"
else
    echo -e "${R}[-] Wordlist not found, skipping bruteforce.${N}"
    touch "$OUT_DIR/active/bruteforce-results.txt"
fi

echo -e "${B}[*] Running Alterx permutations...${N}"
cat "$OUT_DIR/passive/passive-subdomain.txt" | alterx -silent | puredns resolve | tee "$OUT_DIR/active/permutations.txt" > /dev/null
PERM_COUNT=$(wc -l < "$OUT_DIR/active/permutations.txt" 2>/dev/null || echo 0)
echo -e "${Y}[!] Permutations found $PERM_COUNT resolved subdomains.${N}"

# Phase 4: Public Exposure Probing
echo -e "${G}[+] Phase 4: Combining & Web Probing...${N}"
cat "$OUT_DIR/active/resolved.txt" "$OUT_DIR/active/bruteforce-results.txt" "$OUT_DIR/active/permutations.txt" | sort -u > "$OUT_DIR/active/final-resolved.txt"
FINAL_COUNT=$(wc -l < "$OUT_DIR/active/final-resolved.txt" 2>/dev/null || echo 0)
echo -e "${B}[*] Total Unique Subdomains: $FINAL_COUNT${N}"

httpx -l "$OUT_DIR/active/final-resolved.txt" -title -status-code -ip -cname -tech-detect -o "$OUT_DIR/web/metadata.txt" -silent
echo -e "${Y}[!] Web metadata saved to $OUT_DIR/web/metadata.txt${N}"

# Phase 5: Network Exposure
echo -e "${G}[+] Phase 5: Network Service Discovery...${N}"
PORTS="21,22,3306,5432,27017,6379,9200"
naabu -l "$OUT_DIR/active/final-resolved.txt" -p "$PORTS" -rate "$RATE" -o "$OUT_DIR/network/services.txt" -silent
echo -e "${Y}[!] Port scanning complete.${N}"

echo -e "${B}[*] Running Nmap version detection on main domain...${N}"
nmap -sV -p- --min-rate "$RATE" "$DOMAIN" -oN "$OUT_DIR/network/nmap_report.txt" > /dev/null

# Final Processing
echo -e "${G}[+] Generating Final Reports...${N}"
python3 formatter.py "$OUT_DIR"

echo -e "${B}[*] All Done! Summary available in: $OUT_DIR/reports/${N}"
