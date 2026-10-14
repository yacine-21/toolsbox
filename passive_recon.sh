#!/usr/bin/env bash
# =============================================================================
# passive_recon.sh — Recon externe PASSIF (0 interaction avec la cible)
# -----------------------------------------------------------------------------
# Chaîne les phases 1->5 du playbook "OSINT - Passive Recon (Zero Interaction)" :
#   WHOIS + ASN/netblock  ->  crt.sh (CT)  ->  subfinder/amass/assetfinder (passif)
#   ->  Shodan (host + org).  Aucune requete n'est envoyee a l'infra de la cible.
#
# Par defaut : 100% passif (aucune resolution DNS, aucun probe HTTP de la cible).
# L'option --active-probe (opt-in explicite) ajoute dnsx+httpx : ca TOUCHE la
# cible -> a n'utiliser QUE dans un scope actif autorise.
#
# Usage :
#   ./passive_recon.sh -D ascendeo.fr
#   ./passive_recon.sh -d domains.txt -t targets.txt -o out/
#   ./passive_recon.sh -d domains.txt --active-probe        # 🟡 sort du passif
#
# Cles API (env, toutes optionnelles — le script degrade proprement) :
#   SHODAN_API_KEY               Shodan (ou `shodan init` deja fait)          Phase 5
#   ST_KEY                       SecurityTrails (subs + historique A)          Phase 2
#   VT_KEY                       VirusTotal (subdomains)                       Phase 2
#   HIBP_KEY                     HaveIBeenPwned (breacheddomain)               Phase 7
#   DEHASHED_USER / DEHASHED_KEY Dehashed (creds en fuite)                    Phase 7
#   GH_ORG / GITHUB_TOKEN        trufflehog github --org (secrets repos pub)  Phase 8
#   CLOUD_KEYWORDS               mots-cles cloud_enum en plus (ex: "lick muvit") Phase 9
#   HARV_SOURCES                 sources theHarvester (defaut: passives)      Phase 6
#   Les cles subfinder/amass se configurent dans leurs YAML (voir OSINT-API-Keys).
#
# Outils attendus (Kali) : whois jq curl subfinder amass assetfinder shodan
#   theHarvester gau waybackurls trufflehog cloud_enum  (+ dnsx httpx en actif).
#   Un outil absent = phase sautee proprement (jamais de crash).
# =============================================================================
set -euo pipefail

# ------------------------------------------------------------------ args -----
DOMAINS_FILE=""; TARGETS_FILE=""; SINGLE_DOMAIN=""; OUTDIR=""; ACTIVE=0
usage(){ grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    -D) SINGLE_DOMAIN="$2"; shift 2;;
    -d) DOMAINS_FILE="$2";  shift 2;;
    -t) TARGETS_FILE="$2";  shift 2;;
    -o) OUTDIR="$2";        shift 2;;
    --active-probe) ACTIVE=1; shift;;
    -h|--help) usage 0;;
    *) echo "arg inconnu : $1" >&2; usage 1;;
  esac
done

# domaines -> fichier de travail
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
DOMAINS="$WORK/domains.txt"
if [[ -n "$SINGLE_DOMAIN" ]]; then echo "$SINGLE_DOMAIN" > "$DOMAINS"
elif [[ -n "$DOMAINS_FILE" ]]; then grep -vE '^\s*$' "$DOMAINS_FILE" | sort -u > "$DOMAINS"
else echo "[!] Fournis -D <domaine> ou -d <domains.txt>" >&2; usage 1; fi

OUTDIR="${OUTDIR:-passive_recon_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUTDIR"
SUBS="$OUTDIR/subdomains.txt"; : > "$SUBS"

c(){ printf '\033[1;36m%s\033[0m\n' "$*"; }        # cyan
ok(){ printf '\033[1;32m  [+] %s\033[0m\n' "$*"; }
warn(){ printf '\033[1;33m  [~] %s\033[0m\n' "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }
CURL="curl -s --max-time ${HTTP_TIMEOUT:-20}"       # jamais de hang sur un tiers lent
WHOIS(){ timeout "${WHOIS_TIMEOUT:-15}" whois "$@" 2>/dev/null || true; }
# append-only + dedup final : aucune dépendance (pas de `anew`), flux jamais perdu
merge_subs(){ sed 's/\*\.//g' | tr 'A-Z' 'a-z' | grep -E '^[a-z0-9._-]+\.[a-z]{2,}$' >> "$SUBS" || true; }

c "=== passive_recon — sortie : $OUTDIR ==="

# ============================ Phase 1 — WHOIS + ASN/netblock  🟢 ==============
c "[Phase 1] WHOIS + ASN / netblock"
: > "$OUTDIR/whois.txt"; : > "$OUTDIR/asn.txt"
while read -r d; do
  { echo "########## $d ##########"; WHOIS "$d" \
      | grep -iE 'registrar:|registrant|name server|nserver|creation|expir' | sort -u || true; } >> "$OUTDIR/whois.txt"
done < "$DOMAINS"
ok "whois domaines -> whois.txt"

if [[ -n "$TARGETS_FILE" && -f "$TARGETS_FILE" ]]; then
  while read -r ip; do
    [[ -z "$ip" ]] && continue
    ip_only="${ip%%/*}"
    { echo "########## $ip ##########"; WHOIS "$ip_only" \
        | grep -iE 'netname|inetnum|origin|orgname|org-name|country|abuse-mailbox' | sort -u || true; } >> "$OUTDIR/whois.txt"
    if have jq; then
      # pivot ASN -> prefixes de l'orga (base tierce bgpview, 0 contact cible)
      $CURL "https://api.bgpview.io/ip/$ip_only" 2>/dev/null \
        | jq -r '.data.prefixes[]? | "\(.prefix)\t\(.name // "?")\tAS\(.asn.asn)"' >> "$OUTDIR/asn.txt" || true
    fi
  done < "$TARGETS_FILE"
  sort -u "$OUTDIR/asn.txt" -o "$OUTDIR/asn.txt" 2>/dev/null || true
  ok "whois IP + prefixes ASN -> asn.txt ($(wc -l < "$OUTDIR/asn.txt" 2>/dev/null || echo 0) préfixes)"
else
  warn "pas de -t targets.txt -> phase IP/ASN sautée"
fi

# ============================ Phase 2 — Passive DNS (SecurityTrails / VT)  🟢 =
c "[Phase 2] Passive DNS — subdomains + historique A (vraie IP derrière CDN/WAF)"
DNSHIST="$OUTDIR/dns_history.txt"; : > "$DNSHIST"
if [[ -z "${ST_KEY:-}${VT_KEY:-}" ]]; then
  warn "ni ST_KEY (SecurityTrails) ni VT_KEY (VirusTotal) -> Phase 2 sautée (voir OSINT-API-Keys)"
else
  while read -r d; do
    if [[ -n "${ST_KEY:-}" ]] && have jq; then
      # sous-domaines (préfixes -> FQDN)
      $CURL "https://api.securitytrails.com/v1/domain/$d/subdomains?apikey=$ST_KEY" \
        | jq -r --arg d "$d" '.subdomains[]? + "." + $d' 2>/dev/null | merge_subs || true
      # historique des A records -> IP d'origine (bypass CDN/WAF plus tard)
      $CURL "https://api.securitytrails.com/v1/history/$d/dns/a?apikey=$ST_KEY" \
        | jq -r --arg d "$d" '.records[]? | .first_seen as $f | .last_seen as $l
            | .values[]? | "\($d)\t\(.ip)\t\($f)..\($l)"' 2>/dev/null >> "$DNSHIST" || true
    fi
    if [[ -n "${VT_KEY:-}" ]] && have jq; then
      $CURL -H "x-apikey: $VT_KEY" "https://www.virustotal.com/api/v3/domains/$d/subdomains?limit=40" \
        | jq -r '.data[]?.id' 2>/dev/null | merge_subs || true
    fi
  done < "$DOMAINS"
  sort -u "$SUBS" -o "$SUBS" 2>/dev/null || true
  sort -u "$DNSHIST" -o "$DNSHIST" 2>/dev/null || true
  ok "passive DNS -> subs enrichis ($(wc -l < "$SUBS")) · historique A -> dns_history.txt ($(wc -l < "$DNSHIST" 2>/dev/null || echo 0))"
fi

# ============================ Phase 3 — Certificate Transparency  🟢 =========
c "[Phase 3] crt.sh (Certificate Transparency)"
while read -r d; do
  dre="$(printf '%s' "$d" | sed 's/\./\\./g')"      # échappe les points pour le grep
  $CURL "https://crt.sh/?q=%25.${d}&output=json" \
    | jq -r '.[].name_value' 2>/dev/null | tr ',' '\n' \
    | grep -iE "(^|\.)${dre}\$" | merge_subs || true   # coupe les FP crt.sh (testexample.com)
done < "$DOMAINS"
sort -u "$SUBS" -o "$SUBS" 2>/dev/null || true
ok "crt.sh -> subdomains.txt (cumul $(wc -l < "$SUBS") lignes)"

# ============================ Phase 4 — subdomains passif  🟢 ================
c "[Phase 4] subfinder / amass / assetfinder (passif)"
while read -r d; do
  have subfinder   && subfinder -d "$d" -all -silent 2>/dev/null | merge_subs || warn "subfinder absent"
  have assetfinder && assetfinder --subs-only "$d" 2>/dev/null | merge_subs   || true
  have amass       && amass enum -passive -d "$d" -silent 2>/dev/null | merge_subs || warn "amass absent"
done < "$DOMAINS"
sort -u "$SUBS" -o "$SUBS"
ok "sous-domaines uniques : $(wc -l < "$SUBS")  -> $SUBS"

# ============================ Phase 5 — Shodan  🟢 ==========================
c "[Phase 5] Shodan (host + org)"
SHODAN_OUT="$OUTDIR/shodan.txt"; : > "$SHODAN_OUT"
shodan_host(){  # 1=ip
  if have shodan; then shodan host "$1" 2>/dev/null
  elif [[ -n "${SHODAN_API_KEY:-}" ]] && have jq; then
    $CURL "https://api.shodan.io/shodan/host/$1?key=$SHODAN_API_KEY" \
      | jq -r '"IP \(.ip_str)  \(.org // "")\nports: \(.ports|tostring)\n" + ([.data[]? | "  \(.port)/\(.transport//"tcp") \(.product//"") \(._shodan.module//"")"]|join("\n"))' 2>/dev/null
  fi
}
if have shodan || [[ -n "${SHODAN_API_KEY:-}" ]]; then
  if [[ -n "$TARGETS_FILE" && -f "$TARGETS_FILE" ]]; then
    while read -r ip; do [[ -z "$ip" ]] && continue
      { echo "########## $ip ##########"; shodan_host "${ip%%/*}" || true; echo; } >> "$SHODAN_OUT"
    done < "$TARGETS_FILE"
    ok "shodan host -> shodan.txt"
  else warn "pas de -t targets.txt -> shodan host sauté"; fi
  # rattachement par org / cert (best-effort via CLI)
  if have shodan; then
    while read -r d; do org="${d%.*}"
      shodan search --limit 50 "ssl.cert.subject.CN:$d" 2>/dev/null >> "$OUTDIR/shodan_cert_$d.txt" || true
    done < "$DOMAINS"
  fi
else
  warn "ni CLI shodan ni SHODAN_API_KEY -> Phase 5 sautée (voir OSINT-API-Keys)"
fi

# ============================ Phase 6 — OSINT emails / employés  🟢 ==========
c "[Phase 6] OSINT emails / employés (theHarvester)"
EMAILS="$OUTDIR/emails.txt"; USERS="$OUTDIR/users.txt"; : > "$EMAILS"
HARV_SOURCES="${HARV_SOURCES:-crtsh,bing,duckduckgo,otx,rapiddns,urlscan,hackertarget,threatminer,anubis}"
while read -r d; do
  f="$OUTDIR/harvester_$d"
  theHarvester -d "$d" -b "$HARV_SOURCES" -f "$f" >/dev/null 2>&1 || true
  if [[ -f "$f.json" ]] && have jq; then
    jq -r '.emails[]?' "$f.json" 2>/dev/null >> "$EMAILS" || true
    jq -r '.hosts[]?'  "$f.json" 2>/dev/null | sed 's/:.*//' | merge_subs || true   # hosts -> subs
  fi
done < "$DOMAINS"
sort -u "$EMAILS" -o "$EMAILS" 2>/dev/null || true
sed 's/@.*//' "$EMAILS" 2>/dev/null | sort -u > "$USERS" || true   # partie locale = users pour spray
sort -u "$SUBS" -o "$SUBS" 2>/dev/null || true
ok "emails -> emails.txt ($(wc -l < "$EMAILS")) · users -> users.txt ($(wc -l < "$USERS" 2>/dev/null || echo 0))"

# ============================ Phase 7 — Fuites de credentials  🟢 ============
c "[Phase 7] Fuites de credentials (HIBP / Dehashed)"
LEAKS="$OUTDIR/leaks.txt"; : > "$LEAKS"
if [[ -z "${HIBP_KEY:-}${DEHASHED_KEY:-}" ]]; then
  warn "ni HIBP_KEY ni DEHASHED_KEY -> Phase 7 sautée (voir OSINT-API-Keys)"
else
  while read -r d; do
    if [[ -n "${HIBP_KEY:-}" ]] && have jq; then
      { echo "== HIBP $d =="; $CURL -H "hibp-api-key: $HIBP_KEY" -H "user-agent: passive_recon" \
          "https://haveibeenpwned.com/api/v3/breacheddomain/$d" | jq . 2>/dev/null; } >> "$LEAKS" || true
    fi
    if [[ -n "${DEHASHED_KEY:-}" && -n "${DEHASHED_USER:-}" ]] && have jq; then
      { echo "== Dehashed $d =="; $CURL -u "$DEHASHED_USER:$DEHASHED_KEY" -H 'Accept: application/json' \
          "https://api.dehashed.com/search?query=domain:$d" \
          | jq -r '.entries[]? | "\(.email):\(.password // .hashed_password // "")"' 2>/dev/null; } >> "$LEAKS" || true
    fi
  done < "$DOMAINS"
  ok "fuites -> leaks.txt ($(grep -c ':' "$LEAKS" 2>/dev/null | head -1) lignes potentielles)"
fi

# ============================ Phase 8 — Wayback URLs + fuites de code  🟢 ====
c "[Phase 8] Wayback URLs (gau/waybackurls) + secrets (trufflehog)"
WB="$OUTDIR/wayback_urls.txt"; : > "$WB"
while read -r d; do
  gau "$d"         2>/dev/null >> "$WB" || true    # archive.org / CommonCrawl / OTX (0 contact cible)
  waybackurls "$d" 2>/dev/null >> "$WB" || true
done < "$DOMAINS"
sort -u "$WB" -o "$WB" 2>/dev/null || true
ok "wayback -> wayback_urls.txt ($(wc -l < "$WB"))"
# secrets sur repos publics d'une orga GitHub (GH_ORG=nom-orga ; GITHUB_TOKEN pour le quota)
if [[ -n "${GH_ORG:-}" ]]; then
  trufflehog github --org="$GH_ORG" --only-verified 2>/dev/null > "$OUTDIR/secrets.txt" || true
  ok "trufflehog github --org=$GH_ORG -> secrets.txt ($(wc -l < "$OUTDIR/secrets.txt" 2>/dev/null || echo 0))"
else
  warn "GH_ORG non défini -> scan secrets GitHub sauté (ex: GH_ORG=ascendeo)"
fi

# ============================ Phase 9 — Assets cloud  🟡 (borderline) ========
c "[Phase 9] Assets cloud (cloud_enum) — 🟡 teste des noms de buckets côté AWS/Azure/GCP"
CLOUD="$OUTDIR/cloud.txt"; : > "$CLOUD"
KW=(); while read -r d; do KW+=("-k" "${d%%.*}"); done < "$DOMAINS"   # label principal (ascendeo)
for extra in ${CLOUD_KEYWORDS:-}; do KW+=("-k" "$extra"); done         # mots-clés en plus (marques)
cloud_enum "${KW[@]}" -l "$CLOUD" >/dev/null 2>&1 || true
ok "cloud_enum -> cloud.txt ($(wc -l < "$CLOUD" 2>/dev/null || echo 0)) · 🟡 lister/DL un bucket = touche le stockage"

# ============================ 🟡 Bascule active (opt-in) =====================
if [[ "$ACTIVE" -eq 1 ]]; then
  c "[🟡 ACTIF] Résolution + probe HTTP — CECI TOUCHE LA CIBLE (scope requis)"
  RESOLVED="$OUTDIR/resolved.txt"; LIVE="$OUTDIR/live_http.txt"
  if have dnsx;  then dnsx  -l "$SUBS" -silent -a -resp 2>/dev/null > "$RESOLVED"; ok "dnsx -> resolved.txt ($(wc -l < "$RESOLVED") vivants)"; else warn "dnsx absent"; fi
  if have httpx; then httpx -l "$SUBS" -silent -title -tech-detect -status-code 2>/dev/null > "$LIVE"; ok "httpx -> live_http.txt ($(wc -l < "$LIVE") services)"; else warn "httpx absent"; fi
else
  c "[i] Mode passif — aucune résolution DNS ni probe HTTP de la cible."
  echo "    (Phase 9 cloud_enum teste des noms de buckets côté fournisseurs = seul contact indirect.)"
  echo "    Pour résoudre/prober la cible (🟡, scope requis) : relance avec --active-probe"
fi

# ============================ Récap ========================================
c "=== Terminé ==="
printf '  domaines racine : %s\n' "$(wc -l < "$DOMAINS")"
printf '  sous-domaines   : %s\n' "$(wc -l < "$SUBS")"
printf '  historique DNS  : %s (dns_history.txt = IP réelles)\n' "$(wc -l < "$OUTDIR/dns_history.txt" 2>/dev/null || echo 0)"
printf '  emails / users  : %s / %s\n' "$(wc -l < "$OUTDIR/emails.txt" 2>/dev/null || echo 0)" "$(wc -l < "$OUTDIR/users.txt" 2>/dev/null || echo 0)"
printf '  fuites creds    : %s (leaks.txt)\n' "$(grep -c ':' "$OUTDIR/leaks.txt" 2>/dev/null | head -1)"
printf '  wayback URLs    : %s · cloud : %s\n' "$(wc -l < "$OUTDIR/wayback_urls.txt" 2>/dev/null || echo 0)" "$(wc -l < "$OUTDIR/cloud.txt" 2>/dev/null || echo 0)"
printf '  sortie          : %s/\n' "$OUTDIR"
ls -1 "$OUTDIR"
