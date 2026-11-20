#!/bin/bash
set -euo pipefail

BACKUP_DIR="/mnt/sauvegardes"
DATE=$(date +%Y-%m-%d_%H%M%S)
DEST="$BACKUP_DIR/backup-$DATE"
LATEST="$BACKUP_DIR/latest"
LOG_FILE="/var/log/sauvegarde.log"

exec >> >(tee -a "$LOG_FILE") 2>&1

echo "=== Début de sauvegarde : $DATE ==="

if [ ! -d "$BACKUP_DIR" ]; then
    echo "Erreur : le point de montage $BACKUP_DIR n'existe pas."
    exit 1
fi

# Option link-dest pour l'incrémental
LINK_OPTION=""
if [ -L "$LATEST" ] && [ -d "$LATEST" ]; then
    LINK_OPTION="--link-dest=$LATEST"
fi

# Sauvegarde des données /srv et des configurations /etc
mkdir -p "$DEST"
rsync -aAX --delete $LINK_OPTION /srv /etc "$DEST/"

# Mise à jour du lien symbolique latest
rm -f "$LATEST"
ln -s "$DEST" "$LATEST"

# Droits stricts : accessible uniquement aux administrateurs (B3)
chown -R root:admins "$BACKUP_DIR"
chmod 750 "$BACKUP_DIR"
chmod -R o-rwx "$BACKUP_DIR"

# Conservation des 7 dernières versions (B1)
cd "$BACKUP_DIR"
ls -dt backup-* 2>/dev/null | tail -n +8 | while read -r old_backup; do
    echo "Suppression de l'ancienne sauvegarde : $old_backup"
    rm -rf "$old_backup"
done

echo "=== Sauvegarde terminée avec succès : $(date) ==="