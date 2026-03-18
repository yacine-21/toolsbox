#!/bin/bash

DOMAIN=$1
USERNAME=$2
EXCLUDE_FILE=$3

if [[ -z "$DOMAIN" || -z "$USERNAME" ]]; then
    echo -e "\033[1;31m[-] Usage: $0 <domaine.com> <username> [exclude_file.txt]\033[0m"
    exit 1
fi

USER_AGENT="$USERNAME@intigriti.me"
HEADER="X-Intigriti-Username: $USERNAME"
BASE_DIR="recon_$DOMAIN"
mkdir -p "$BASE_DIR/screenshots"

echo -e "\033[1;34m[*] 1. Énumération passive...\033[0m"
subfinder -d "$DOMAIN" -all -silent > "$BASE_DIR/subfinder_raw.txt"
assetfinder --subs-only "$DOMAIN" >> "$BASE_DIR/assetfinder_raw.txt"

if [[ -f "$EXCLUDE_FILE" ]]; then
    cat "$BASE_DIR"/*_raw.txt | sort -u | grep "$DOMAIN" | grep -vFf "$EXCLUDE_FILE" > "$BASE_DIR/final_subs.txt"
else
    cat "$BASE_DIR"/*_raw.txt | sort -u | grep "$DOMAIN" > "$BASE_DIR/final_subs.txt"
fi

echo -e "\n\033[1;34m[*] 2. Vérification HTTP (Uniquement 200 OK)...\033[0m"
# On enregistre dans alive_200.txt pour être cohérent
cat "$BASE_DIR/final_subs.txt" | httpx -silent -mc 200 -sc -title -td -rl 5 -H "$HEADER" -H "User-Agent: $USER_AGENT" -o "$BASE_DIR/alive_200.txt"

if [ ! -s "$BASE_DIR/alive_200.txt" ]; then
    echo -e "\033[1;31m[-] Erreur : Aucun domaine en code 200 trouvé.\033[0m"
    exit 1
fi

# On crée la liste d'URLs propre
cut -d' ' -f1 "$BASE_DIR/alive_200.txt" > "$BASE_DIR/urls_200_only.txt"

echo -e "\n\033[1;34m[*] 3. Captures d'écran (Gowitness)...\033[0m"
gowitness scan file -f "$BASE_DIR/urls_200_only.txt" \
    --threads 1 \
    --write-db \
    --write-db-uri "sqlite://$BASE_DIR/gowitness.sqlite3" \
    --screenshot-path "$BASE_DIR/screenshots" \
    --chrome-header "$HEADER" \
    --chrome-user-agent "$USER_AGENT"

echo -e "\n\033[1;34m[*] 4. Nuclei sur les hosts UP (200 OK)...\033[0m"

nuclei -l "$BASE_DIR/urls_200_only.txt" -rl 5 -H "$HEADER" -H "User-Agent: $USER_AGENT" -o "$BASE_DIR/nuclei_results.txt"

echo -e "\n\033[1;34m[*] 5. Bonus : Fuzzing rapide sur les cibles 200...\033[0m"
# Utilisation d'une wordlist plus ciblée "Discovery"
#WL="/usr/share/wordlists/dirb/common.txt"
WL="/opt/lists/seclists/Discovery/Web-Content/directory-list-2.3-big.txt"
for target in $(cat "$BASE_DIR/urls_200_only.txt"); do
    echo "[+] Fuzzing: $target"
    ffuf -u "$target/FUZZ" -w "$WL" -mc 200,301 -rate 5 -H "$HEADER" -H "User-Agent: $USER_AGENT" -s
done
