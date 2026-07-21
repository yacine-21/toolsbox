#!/bin/bash
# Extract only domain users from nxc output (supports --rid-brute and --users)

INPUT="${1:-.}"
OUTPUT="${2:-users.txt}"

if [ ! -f "$INPUT" ]; then
    echo "[-] File $INPUT not found."
    exit 1
fi

# Détection du format et extraction
if grep -q 'SidTypeUser' "$INPUT"; then
    # Format --rid-brute (l'utilisateur est dans le 6ème champ sous la forme DOMAIN\user)
    grep 'SidTypeUser' "$INPUT" | awk '{print $6}' | cut -d'\' -f2
else
    # Format --users (l'utilisateur est dans le 5ème champ, on cible les lignes avec dates ou <never>)
    grep -E '[0-9]{4}-[0-9]{2}-[0-9]{2}|<never>' "$INPUT" | awk '{print $5}'
fi | \
    grep -E -v '^(Administrator|Guest|krbtgt|DefaultAccount|WDAGUtilityAccount|None|.*\$)$' | \
    sort -u >> "$OUTPUT"

echo "[+] Users exported to $OUTPUT"
