#!/bin/bash
# grab_kerbrute_users.sh
# Usage: ./grab_kerbrute_users.sh kerbrute_output.txt [output.txt]

INPUT="${1}"
OUTPUT="${2:-users.txt}"

if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
    echo "[-] Usage: $0 <kerbrute_output.txt> [output.txt]"
    exit 1
fi

# Extrait uniquement les usernames valides (sans domaine)
grep -oP 'VALID USERNAME:\s+\K[^\s@]+' "$INPUT" | sort -u > "$OUTPUT"

echo "[+] $(wc -l < "$OUTPUT") users exported to $OUTPUT"
