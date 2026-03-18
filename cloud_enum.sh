#!/bin/bash

# 1. Configuration (Chemin validé par ton 'file')
TARGET=$1
MUTATIONS="/usr/share/wordlists/seclists/Discovery/Web-Content/web-mutations.txt"
SUFFIXES=("dev" "prod" "staging" "storage" "backup" "archive" "public" "data" "test")

if [ -z "$1" ]; then
    echo -e "\e[1;31m[-] Usage: $0 <mot_cle_entreprise>\e[0m"
    echo "Exemple: $0 ysolutionscybertech"
    exit 1
fi

# 2. Nettoyage du TARGET (on retire le .com s'il est présent pour éviter les bugs de noms)
CLEAN_TARGET=$(echo "$TARGET" | sed 's/\.com//g' | sed 's/\.fr//g')

echo -e "\e[1;34m[*] --- PHASE 1 : Vérification rapide (Custom Suffixes) sur $CLEAN_TARGET ---\e[0m"

check_aws() {
    local bucket=$1
    # Utilisation de -I pour être plus rapide (HEAD request)
    status=$(curl -s -I "https://${bucket}.s3.amazonaws.com" | grep HTTP | awk '{print $2}')
    if [ "$status" == "200" ]; then
        echo -e "\e[32m[+] [AWS S3] OUVERT : https://${bucket}.s3.amazonaws.com\e[0m"
    elif [ "$status" == "403" ]; then
        echo -e "\e[33m[!] [AWS S3] EXISTE (Privé) : https://${bucket}.s3.amazonaws.com\e[0m"
    fi
}

# Test initial + Suffixes
check_aws "$CLEAN_TARGET"
for s in "${SUFFIXES[@]}"; do
    check_aws "${CLEAN_TARGET}-${s}"
done

echo -e "\n\e[1;34m[*] --- PHASE 2 : Énumération lourde (cloud_enum + SecLists) ---\e[0m"
# On lance l'outil avec le fichier que tu as trouvé
cloud_enum -k "$CLEAN_TARGET" -m "$MUTATIONS" -t 30 -l "cloud_${CLEAN_TARGET}_full.txt"

echo -e "\n\e[1;32m[!] Terminé. Résultats : cloud_${CLEAN_TARGET}_full.txt\e[0m"
