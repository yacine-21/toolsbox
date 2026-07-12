#!/bin/bash
# Extract only domain users from nxc rid-brute output

INPUT="${1:-.}"
OUTPUT="${2:-users.txt}"

grep 'SidTypeUser' "$INPUT" | \
    sed 's/.*SUPPORT\\//' | \
    awk '{print $1}' | \
    grep '\.' | \
    grep -v '^(Administrator|Guest|krbtgt|DC|ldap)' | \
    sort -u > "$OUTPUT"

echo "[+] Users exported to $OUTPUT"
