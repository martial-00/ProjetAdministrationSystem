#!/bin/bash
set -euo pipefail

SEUIL=${1:-5}

echo "=== RAPPORT D'ANALYSE SSH ==="
echo "Date de l'analyse : $(date '+%Y-%m-%d %H:%M:%S')"
echo "----------------------------------------"

# Extraction des échecs par IP
echo "--- Échecs de connexion par IP ---"
ECHECS_IP=$(journalctl -u ssh --since "24 hours ago" --no-pager | \
    grep -E 'Failed password|Invalid user|not allowed' | \
    grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | \
    sort | uniq -c | sort -rn || true)

if [ -z "$ECHECS_IP" ]; then
    echo "Aucun échec détecté."
else
    echo "$ECHECS_IP"
fi

echo ""
echo "--- Comptes visés ---"
journalctl -u ssh --since "24 hours ago" --no-pager | \
    grep -E 'Failed password|Invalid user' | \
    grep -oE 'for (invalid user )?[a-zA-Z0-9_-]+' | \
    awk '{print $NF}' | sort | uniq -c | sort -rn || echo "Aucun"

echo ""
echo "--- Connexions réussies ---"
journalctl -u ssh --since "24 hours ago" --no-pager | \
    grep 'Accepted' | \
    grep -oE 'Accepted (publickey|password) for [a-zA-Z0-9_-]+ from ([0-9]{1,3}\.){3}[0-9]{1,3}' || echo "Aucune"

# Vérification du seuil d'alerte
ALERTE=0
if [ -n "$ECHECS_IP" ]; then
    while read -r count ip; do
        if [ "$count" -ge "$SEUIL" ]; then
            echo "" >&2
            echo "ALERTE : L'IP $ip dépasse le seuil avec $count échecs !" >&2
            ALERTE=1
        fi
    done <<< "$ECHECS_IP"
fi

exit $ALERTE