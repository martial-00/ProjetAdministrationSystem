#!/bin/bash
set -euo pipefail

CSV_FILE="${1:-/root/projet-pixelia/comptes.csv}"
KEYS_DIR="${2:-/root/projet-pixelia/config/keys}"

if [ "$EUID" -ne 0 ]; then
    echo "Erreur : ce script doit être lancé en root." >&2
    exit 1
fi

if [ ! -f "$CSV_FILE" ]; then
    echo "Erreur : fichier CSV introuvable : $CSV_FILE" >&2
    exit 1
fi

# 1. Création des groupes métier et système
GROUPES=("admins" "support" "acces_ssh" "dev" "design" "commercial" "freelance")
for g in "${GROUPES[@]}"; do
    if ! getent group "$g" >/dev/null; then
        groupadd "$g"
        echo "Groupe créé : $g"
    fi
done

# 2. Lecture et création des comptes (C1)
tail -n +2 "$CSV_FILE" | while IFS=';' read -r login nom g_principal g_secondaires; do
    [ -z "$login" ] && continue

    if ! getent passwd "$login" >/dev/null; then
        useradd -m -s /bin/bash -c "$nom" -g "$g_principal" "$login"
        passwd -l "$login" >/dev/null # Pas de mot de passe direct, clé SSH requise
        echo "Utilisateur créé : $login"
    fi

    # Ajout des groupes secondaires
    if [ -n "$g_secondaires" ]; then
        IFS=',' read -ra SEC_ARR <<< "$g_secondaires"
        for sg in "${SEC_ARR[@]}"; do
            usermod -aG "$sg" "$login"
        done
    fi

    # Particularité Contexte A : Expiration du groupe freelance (30 juin 2026)
    if [ "$g_principal" = "freelance" ]; then
        chage -E "2026-06-30" "$login"
    fi

    # Installation des clés SSH publiques
    KEY_PATH="$KEYS_DIR/${login}.pub"
    if [ -f "$KEY_PATH" ]; then
        USER_HOME=$(eval echo "~$login")
        SSH_DIR="$USER_HOME/.ssh"
        install -d -m 700 -o "$login" -g "$g_principal" "$SSH_DIR"
        install -m 600 -o "$login" -g "$g_principal" "$KEY_PATH" "$SSH_DIR/authorized_keys"
    fi
done

# 3. Création de l'arborescence /srv et configuration des ACL (C2)
mkdir -p /srv/projets/externe /srv/maquettes /srv/clients

# Nettoyage et application des permissions de base
chmod 750 /srv/projets /srv/projets/externe /srv/maquettes /srv/clients
chown root:dev /srv/projets /srv/projets/externe
chown root:design /srv/maquettes
chown root:commercial /srv/clients

# Application du bit setgid pour l'héritage du groupe
chmod g+s /srv/projets /srv/projets/externe /srv/maquettes /srv/clients

# /srv/projets : dev (rw), design (r)
setfacl -b -R /srv/projets
setfacl -m g:dev:rwx,d:g:dev:rwx /srv/projets
setfacl -m g:design:r-x,d:g:design:r-x /srv/projets

# /srv/projets/externe : dev (rw), design (r), freelance (rw)
setfacl -m g:dev:rwx,d:g:dev:rwx /srv/projets/externe
setfacl -m g:design:r-x,d:g:design:r-x /srv/projets/externe
setfacl -m g:freelance:rwx,d:g:freelance:rwx /srv/projets/externe

# /srv/maquettes : design (rw), dev (r), commercial (r)
setfacl -b -R /srv/maquettes
setfacl -m g:design:rwx,d:g:design:rwx /srv/maquettes
setfacl -m g:dev:r-x,d:g:dev:r-x /srv/maquettes
setfacl -m g:commercial:r-x,d:g:commercial:r-x /srv/maquettes

# /srv/clients : commercial (rw)
setfacl -b -R /srv/clients
setfacl -m g:commercial:rwx,d:g:commercial:rwx /srv/clients

echo "Comptes, répertoires et ACL configurés avec succès."