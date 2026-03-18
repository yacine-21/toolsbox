#!/bin/bash
# Template : Énumération Authentifiée via LDAP
TARGET=$1
DOMAIN=$2
USER=$3
PASS=$4
OUTPUT="users_ldap.txt"

if [ -z "$PASS" ]; then 
    echo "[-] Usage: $0 <IP> <DOMAIN> <USER> <PASS>"
    exit 1
fi

echo "[*] Extraction LDAP pour le domaine $DOMAIN..."

# Utilisation de nxc avec le protocole LDAP (plus propre que SMB pour lister les users)
nxc ldap "$TARGET" -u "$USER" -p "$PASS" --users | awk '{print $4}' | grep -vE "Users|---" > "$OUTPUT"

if [ -s "$OUTPUT" ]; then
    echo "[+] $(wc -l < $OUTPUT) utilisateurs récupérés via LDAP."
else
    echo "[-] Échec LDAP. Tentative via RPC/SMB..."
    nxc smb "$TARGET" -u "$USER" -p "$PASS" --users | awk '{print $5}' | cut -d'\' -f2 > "$OUTPUT"
fi
