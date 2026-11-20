#!/bin/bash
set -euo pipefail

SRC_DIR="/root/projet-pixelia"

if [ "$EUID" -ne 0 ]; then
    echo "Erreur : installer.sh doit être lancé en root." >&2
    exit 1
fi

echo "--- 1. Mises à jour et installation des paquets (D1) ---"
apt-get update
apt-get install -y acl openssh-server fail2ban nftables unattended-upgrades rsync python3-systemd

# Activation des mises à jour automatiques de sécurité (D1)
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "--- 2. Préparation du second disque pour les sauvegardes (B1) ---"
DISQUE_SAUV=""
for d in /dev/sdb /dev/vdb; do
    if [ -b "$d" ]; then
        DISQUE_SAUV="$d"
        break
    fi
done

mkdir -p /mnt/sauvegardes
if [ -n "$DISQUE_SAUV" ]; then
    if ! blkid "$DISQUE_SAUV" >/dev/null 2>&1; then
        echo "Formatage du second disque $DISQUE_SAUV..."
        mkfs.ext4 -F "$DISQUE_SAUV"
    fi
    if ! grep -qs "/mnt/sauvegardes" /etc/fstab; then
        UUID=$(blkid -s UUID -o value "$DISQUE_SAUV")
        echo "UUID=$UUID /mnt/sauvegardes ext4 defaults 0 2" >> /etc/fstab
    fi
    systemctl daemon-reload
    mount -a
fi

echo "--- 3. Verrouillage du compte root et sécurité utilisateur (C4) ---"
passwd -l root
chmod 700 /home/* 2>/dev/null || true

echo "--- 4. Déploiement des configurations (C3, S1-S5, J1-J3) ---"
# Sudoers (C3)
cp "$SRC_DIR/config/sudoers.d/"* /etc/sudoers.d/
chmod 440 /etc/sudoers.d/*
visudo -c

# SSH (S1-S5)
cp "$SRC_DIR/config/ssh/sshd_config.d/10-durcissement.conf" /etc/ssh/sshd_config.d/
chmod 644 /etc/ssh/sshd_config.d/10-durcissement.conf
sshd -t

# Fail2ban (J1)
cp "$SRC_DIR/config/fail2ban/jail.d/sshd.conf" /etc/fail2ban/jail.d/
chmod 644 /etc/fail2ban/jail.d/sshd.conf

# Nftables (J2)
cp "$SRC_DIR/config/nftables.conf" /etc/nftables.conf
chmod 755 /etc/nftables.conf
systemctl enable nftables

# Journald persistant (J3)
mkdir -p /etc/systemd/journald.conf.d
cp "$SRC_DIR/config/journald.conf.d/10-persistent.conf" /etc/systemd/journald.conf.d/
chmod 644 /etc/systemd/journald.conf.d/10-persistent.conf

echo "--- 5. Installation des scripts système et création des comptes (C1, C2, B3) ---"
cp "$SRC_DIR/creer_comptes.sh" /usr/local/bin/
cp "$SRC_DIR/analyse_logs.sh" /usr/local/bin/
cp "$SRC_DIR/sauvegarde.sh" /usr/local/bin/
chown root:root /usr/local/bin/*.sh
chmod 755 /usr/local/bin/*.sh

# Exécution de la création des comptes, groupes et ACL (C1, C2)
/usr/local/bin/creer_comptes.sh "$SRC_DIR/comptes.csv" "$SRC_DIR/config/keys"

# Droits stricts sur les dossiers personnels (C4) et le répertoire de sauvegarde (B3)
chmod 700 /home/* 2>/dev/null || true
chown root:admins /mnt/sauvegardes
chmod 750 /mnt/sauvegardes

echo "--- 6. Planification de la sauvegarde (B2) ---"
CRON_JOB="0 2 * * * /usr/local/bin/sauvegarde.sh"
(crontab -l 2>/dev/null | grep -v "sauvegarde.sh" || true ; echo "$CRON_JOB") | crontab -

echo "--- 7. Redémarrage des services ---"
systemctl restart systemd-journald
systemctl restart ssh
systemctl restart fail2ban
systemctl restart nftables

echo "Installation terminée avec succès !"