#!/bin/bash

# Usage: ./full_recon_ad.sh <IP>
IP=$1

if [[ -z "$IP" ]]; then
    echo -e "\033[1;31m[-] Erreur : Tu dois spécifier une IP.\033[0m"
    echo "Usage: $0 <IP>"
    exit 1
fi

echo -e "\033[1;34m[*] Étape 1 : Scan de tous les ports (65535) en cours sur $IP...\033[0m"
# On fait un scan complet, -T4 pour la vitesse, --min-rate pour ne pas y passer la nuit
nmap -p- --min-rate 5000 "$IP" -oN nmap.txt

echo -e "\n\033[1;34m[*] Étape 2 : Extraction des ports ouverts...\033[0m"
PORTS=$(grep "open" nmap.txt | awk -F'/' '{print $1}' | grep -E '^[0-9]+$' | tr '\n' ',' | sed 's/,$//')

if [[ -z "$PORTS" ]]; then
    echo -e "\033[1;31m[-] Aucun port ouvert trouvé. La machine est peut-être down ou filtre les ICMP.\033[0m"
    exit 1
fi

echo -e "\033[1;32m[+] Ports détectés : $PORTS\033[0m"

echo -e "\n\033[1;34m[*] Étape 3 : Scan agressif Nmap (Scripts & Versions) sur les ports cibles...\033[0m"
nmap -p"$PORTS" -A -Pn "$IP" -oN scan_agressif.txt

echo -e "\n\033[1;34m[*] Étape 4 : Énumération Active Directory avec NetExec...\033[0m"

echo -e "\033[1;33m--- SMB ---\033[0m"
nxc smb "$IP"
nxc smb "$IP" -u '' -p '' --shares

echo -e "\n\033[1;33m--- LDAP ---\033[0m"
# On essaie de lister les infos sans authentification
nxc ldap "$IP" -u '' -p '' --users --groups --password-not-required

echo -e "\n\033[1;32m[+] Terminé ! Analyse scan_agressif.txt pour les détails des services.\033[0m"
