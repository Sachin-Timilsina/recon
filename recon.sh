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
THREADS="50"

usage() {
    echo -e "${Y}Usage: $0 -d <domain> [-v] [-w <wordlist>] [-m <packet_rate>] [-t <threads>]${N}"
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

# --- STRUCTURE LOGIC ---
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BASE_DIR="recon_${DOMAIN}_${TIMESTAMP}"
mkdir -p "$BASE_DIR"

echo -e "${B}[*] Target: $DOMAIN | Folder: $BASE_DIR${N}"

# Phase 1: Passive
echo -e "${G}[+] Phase 1: Passive DNS Discovery...${N}"
subfinder -d "$DOMAIN" $VERBOSE -o "$BASE_DIR/passive-subdomains.txt" > /dev/null 2>&1
echo -e "${Y}[!] Found $(wc -l < "$BASE_DIR/passive-subdomains.txt") passive subdomains.${N}"

# Phase 2: DNS Resolution
echo -e "${G}[+] Phase 2: DNS Resolution...${N}"
cat "$BASE_DIR/passive-subdomains.txt" | puredns resolve --rate-limit "$THREADS" | tee "$BASE_DIR/resolved.txt" > /dev/null
echo -e "${Y}[!] $(wc -l < "$BASE_DIR/resolved.txt") subdomains resolved.${N}"

# Phase 3: Active Discovery
echo -e "${G}[+] Phase 3: Active Discovery...${N}"
if [ -f "$WORDLIST" ]; then
    puredns bruteforce "$WORDLIST" "$DOMAIN" --rate-limit "$THREADS" -w "$BASE_DIR/bruteforce-results.txt" > /dev/null
else
    echo -e "${R}[-] Wordlist not found, skipping.${N}"
    touch "$BASE_DIR/bruteforce-results.txt"
fi

echo -e "${B}[*] Running Alterx permutations...${N}"
cat "$BASE_DIR/passive-subdomains.txt" | alterx -silent | puredns resolve --rate-limit "$THREADS" | tee "$BASE_DIR/permutations.txt" > /dev/null

# Phase 4: Web Probing
echo -e "${G}[+] Phase 4: Combining & Web Probing...${N}"
cat "$BASE_DIR/resolved.txt" "$BASE_DIR/bruteforce-results.txt" "$BASE_DIR/permutations.txt" | sort -u > "$BASE_DIR/all-live-subs.txt"

httpx -l "$BASE_DIR/all-live-subs.txt" -title -status-code -ip -cname -tech-detect -t "$THREADS" -o "$BASE_DIR/metadata.txt" -silent
echo -e "${Y}[!] Total Unique: $(wc -l < "$BASE_DIR/all-live-subs.txt"). Metadata saved.${N}"

# Phase 5: Network Exposure
echo -e "${G}[+] Phase 5: Network Service Discovery...${N}"
PORTS="21,22,3306,5432,27017,6379,9200"
naabu -l "$BASE_DIR/all-live-subs.txt" -p "$PORTS" -rate "$RATE" -o "$BASE_DIR/services.txt" -silent
nmap -sV -p- --min-rate "$RATE" "$DOMAIN" -oN "$BASE_DIR/nmap_report.txt" > /dev/null

# Final Processing
# We pass the directory to Python so it knows where to find the files
python3 formatter.py "$BASE_DIR"

echo -e "${B}[*] Recon Complete. Report: $BASE_DIR/recon_report.md${N}"
