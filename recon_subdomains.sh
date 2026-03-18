#!/bin/bash

# Vérification des outils
for cmd in curl jq host; do
    command -v $cmd &> /dev/null || { echo "[-] Installe $cmd"; exit 1; }
done

if [ -z "$1" ]; then
    echo "Usage: $0 <domaine>"
    exit 1
fi

TARGET=$1
DATE=$(date +%Y%m%d_%H%M)
BASE_DIR="recon_${TARGET}_${DATE}"

# --- Structure des dossiers ---
echo "[*] Initialisation du dossier : $BASE_DIR"
mkdir -p "$BASE_DIR"/{hosts,ips,raw}

# --- 1. Récupération Passive ---
echo "[*] Récupération des sous-domaines (crt.sh)..."
curl -s "https://crt.sh/?q=${TARGET}&output=json" | \
    jq -r '.[].name_value' | sed 's/\*\.//g' | sort -u > "$BASE_DIR/raw/subdomains_found.txt"

# --- 2. Résolution et Organisation ---
echo "[*] Résolution DNS en cours..."

while read -r sub; do
    # On résout l'IP
    ip=$(host "$sub" | grep "has address" | cut -d" " -f4 | head -n1)

    if [ -n "$ip" ]; then
        # On enregistre dans la liste globale
        echo "$sub : $ip" >> "$BASE_DIR/hosts/resolved_hosts.txt"
        # On crée un fichier d'IP unique pour Nmap plus tard
        echo "$ip" >> "$BASE_DIR/ips/unique_ips.txt"
        echo -e "\e[32m[+] $sub -> $ip\e[0m"
    else
        echo "$sub" >> "$BASE_DIR/hosts/unresolved_hosts.txt"
    fi
done < "$BASE_DIR/raw/subdomains_found.txt"

# Nettoyage des IPs (doublons)
if [ -f "$BASE_DIR/ips/unique_ips.txt" ]; then
    sort -u -o "$BASE_DIR/ips/unique_ips.txt" "$BASE_DIR/ips/unique_ips.txt"
fi

echo -e "\n[!] Travail terminé. Résultats dans : $BASE_DIR"
