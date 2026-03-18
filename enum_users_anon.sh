#!/bin/bash
# Template : Énumération Anonyme Robuste
TARGET=$1
OUTPUT="users_anon.txt"

if [ -z "$TARGET" ]; then 
    echo "[-] Usage: $0 <IP>"
    exit 1
fi

echo "[*] Tentative d'énumération RID brute-force sur $TARGET..."

# On capture l'output, on cherche les lignes (SidTypeUser)
# Puis on extrait uniquement la partie après le backslash \
nxc smb "$TARGET" -u 'guest' -p '' --rid-brute 10000 | \
grep '(SidTypeUser)' | \
grep -oP '[^\s]+\\[^\s]+' | \
cut -d'\' -f2 | \
grep -v '\$' | \
sed '/^$/d' > "$OUTPUT"

if [ -s "$OUTPUT" ]; then
    sort -u "$OUTPUT" -o "$OUTPUT"
    echo "[+] Succès ! $(wc -l < $OUTPUT) utilisateurs extraits dans $OUTPUT"
    echo "--- Extrait ---"
    head -n 5 "$OUTPUT"
else
    echo "[-] Erreur : Le fichier est vide. Vérifie si 'guest' a les droits."
fi
