#!/bin/bash

# Vérification de l'argument
if [ -z "$1" ]; then
    echo "Usage: $0 <domaine>"
    echo "Exemple: $0 inlanefreight.com"
    exit 1
fi

TARGET=$1

echo "[+] Recherche de sous-domaines pour : $TARGET"

# Exécution de la chaîne de commandes
curl -s "https://crt.sh/?q=${TARGET}&output=json" | \
    jq -r '.[].name_value' | \
    sed 's/\*\.//g' | \
    sort -u
