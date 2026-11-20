#!/bin/bash

REUSSIS=0
ECHECS=0

ok() {
    echo -e "[\e[32mOK\e[0m] $1 : $2"
    REUSSIS=$((REUSSIS + 1))
}

ko() {
    echo -e "[\e[31mKO\e[0m] $1 : $2"
    ECHECS=$((ECHECS + 1))
}

# C1: Vérification de l'existence des utilisateurs et groupes
test_C1_comptes() {
    local err=0
    for u in martial gabriel joao support dev1 dev2 design1 design2 com1 com2 free1 free2; do
        if ! getent passwd "$u" >/dev/null; then err=1; fi
    done
    if [ "$err" -eq 0 ]; then ok "C1" "Tous les comptes du fichier CSV existent"; else ko "C1" "Certains comptes sont manquants"; fi
}

test_C1_idempotence() {
    if /usr/local/bin/creer_comptes.sh >/dev/null 2>&1; then
        ok "C1" "creer_comptes.sh est idempotent"
    else
        ko "C1" "creer_comptes.sh renvoie une erreur au second lancement"
    fi
}

# C2: Permissions et ACLs sur /srv
test_C2_projets_dev() {
    if sudo -u dev1 test -w /srv/projets; then ok "C2" "dev a l'accès écriture sur /srv/projets"; else ko "C2" "dev refusé sur /srv/projets"; fi
}

test_C2_projets_design() {
    if sudo -u design1 test -r /srv/projets && ! sudo -u design1 test -w /srv/projets; then
        ok "C2" "design a accès en lecture seule sur /srv/projets"
    else
        ko "C2" "Droits design incorrects sur /srv/projets"
    fi
}

test_C2_projets_commercial() {
    if ! sudo -u com1 test -r /srv/projets; then ok "C2" "commercial n'a pas accès à /srv/projets"; else ko "C2" "commercial peut lire /srv/projets"; fi
}

test_C2_externe_freelance() {
    if sudo -u free1 test -w /srv/projets/externe; then ok "C2" "freelance peut écrire dans /srv/projets/externe"; else ko "C2" "freelance refusé sur /srv/projets/externe"; fi
}

test_C2_maquettes_commercial() {
    if sudo -u com1 test -r /srv/maquettes && ! sudo -u com1 test -w /srv/maquettes; then
        ok "C2" "commercial lit /srv/maquettes en lecture seule"
    else
        ko "C2" "Droits commercial incorrects sur /srv/maquettes"
    fi
}

test_C2_clients_dev() {
    if ! sudo -u dev1 test -r /srv/clients; then ok "C2" "dev n'a pas accès à /srv/clients"; else ko "C2" "dev accède à /srv/clients"; fi
}

test_C2_acl_defaut() {
    touch /srv/projets/test_acl.txt
    if getfacl /srv/projets/test_acl.txt 2>/dev/null | grep -q "group:dev:rwx"; then
        ok "C2" "Les ACL par défaut (héritage) fonctionnent sur /srv/projets"
    else
        ko "C2" "Héritage des ACL défaillant sur /srv/projets"
    fi
    rm -f /srv/projets/test_acl.txt
}

# C3: Droits Sudo
test_C3_admins_sudo() {
    if sudo -l -U martial | grep -q "(ALL : ALL) ALL"; then ok "C3" "Les membres de admins ont plein droit sudo"; else ko "C3" "Sudo admins non conforme"; fi
}

test_C3_support_sudo() {
    if sudo -l -U support | grep -q "(root) NOPASSWD: /usr/local/bin/analyse_logs.sh" && ! sudo -l -U support | grep -q "(ALL"; then
        ok "C3" "Le compte support ne peut exécuter que analyse_logs.sh"
    else
        ko "C3" "Droits sudo de support non conformes"
    fi
}

test_C3_freelance_sudo() {
    if ! sudo -l -U free1 2>&1 | grep -q "may run"; then ok "C3" "Les freelances n'ont aucun accès sudo"; else ko "C3" "Freelance possède des droits sudo"; fi
}

# C4: Verrouillage root et home
test_C4_root_locked() {
    if passwd -S root | grep -qE 'L|P'; then ok "C4" "Le compte root est verrouillé"; else ko "C4" "Le compte root n'est pas verrouillé"; fi
}

test_C4_home_permissions() {
    if [ "$(stat -c "%a" /home/* | grep -v "700" | wc -l)" -eq 0 ]; then ok "C4" "Les répertoires /home sont stricts (700)"; else ko "C4" "Certains /home sont trop ouverts"; fi
}

# SSH (S1 - S5)
test_S1_no_password() {
    if sshd -T | grep -qi '^passwordauthentication no$'; then ok "S1" "Authentification mot de passe désactivée"; else ko "S1" "PasswordAuthentication est actif"; fi
}

test_S2_no_root_ssh() {
    if sshd -T | grep -qi '^permitrootlogin no$'; then ok "S2" "Connexion root SSH interdite"; else ko "S2" "PermitRootLogin n'est pas à no"; fi
}

test_S3_allowgroups() {
    if sshd -T | grep -qi '^allowgroups acces_ssh$'; then ok "S3" "Accès SSH restreint au groupe acces_ssh"; else ko "S3" "AllowGroups incorrect"; fi
}

test_S4_max_tries() {
    local tries
    tries=$(sshd -T | grep -i '^maxauthtries' | awk '{print $2}')
    if [ "$tries" -le 4 ]; then ok "S4" "MaxAuthTries est restreint ($tries <= 4)"; else ko "S4" "MaxAuthTries trop élevé"; fi
}

test_S5_sshd_config_d() {
    if [ -f /etc/ssh/sshd_config.d/10-durcissement.conf ] && sshd -t; then ok "S5" "Fichier dans sshd_config.d valide"; else ko "S5" "Fichier sshd_config.d absent ou invalide"; fi
}

# Journaux et défense (J1 - J4)
test_J1_fail2ban() {
    if fail2ban-client status sshd >/dev/null 2>&1; then ok "J1" "Fail2ban est actif sur le service SSH"; else ko "J1" "Fail2ban inactif pour SSH"; fi
}

test_J2_nftables() {
    if nft list ruleset | grep -q "type filter hook input" && nft list ruleset | grep -q "policy drop"; then
        ok "J2" "Pare-feu nftables actif avec politique par défaut DROP"
    else
        ko "J2" "nftables mal configuré ou politique pas en DROP"
    fi
}

test_J3_journald_persistent() {
    if [ -d /var/log/journal ] && systemd-analyze cat-config systemd/journald.conf | grep -qi "Storage=persistent"; then
        ok "J3" "Le journal système est persistant"
    else
        ko "J3" "Journald non persistant"
    fi
}

test_J4_analyse_logs_script() {
    if [ -x /usr/local/bin/analyse_logs.sh ]; then ok "J4" "Le script analyse_logs.sh existe et est exécutable"; else ko "J4" "analyse_logs.sh manquant"; fi
}

# Sauvegardes (B1 - B3)
test_B1_sauvegarde_script() {
    if [ -x /usr/local/bin/sauvegarde.sh ]; then ok "B1" "Le script sauvegarde.sh est présent"; else ko "B1" "sauvegarde.sh absent"; fi
}

test_B2_cron_job() {
    if crontab -l 2>/dev/null | grep -q "sauvegarde.sh"; then ok "B2" "La sauvegarde automatique est planifiée dans cron"; else ko "B2" "Aucune planification cron trouvée"; fi
}

test_B3_backup_permissions() {
    if [ -d /mnt/sauvegardes ] && [ "$(stat -c "%U:%G" /mnt/sauvegardes)" = "root:admins" ]; then
        ok "B3" "Le répertoire de sauvegarde est restreint à root:admins"
    else
        ko "B3" "Droits sur /mnt/sauvegardes incorrects"
    fi
}

# Système (D1 - D2)
test_D1_unattended_upgrades() {
    if dpkg -l | grep -q unattended-upgrades; then ok "D1" "unattended-upgrades est installé"; else ko "D1" "unattended-upgrades absent"; fi
}

test_D2_listening_ports() {
    local ports
    ports=$(ss -tulpn | grep LISTEN | grep -v '127.0.0.1' | grep -v '::1' | grep -vc '22')
    if [ "$ports" -eq 0 ]; then ok "D2" "Seul le service SSH écoute sur le réseau externe"; else ko "D2" "Des services non autorisés écoutent sur le réseau"; fi
}

# Exécution des tests
echo "=== DÉBUT DES VERIFICATIONS AUTOMATIQUES ==="
test_C1_comptes
test_C1_idempotence
test_C2_projets_dev
test_C2_projets_design
test_C2_projets_commercial
test_C2_externe_freelance
test_C2_maquettes_commercial
test_C2_clients_dev
test_C2_acl_defaut
test_C3_admins_sudo
test_C3_support_sudo
test_C3_freelance_sudo
test_C4_root_locked
test_C4_home_permissions
test_S1_no_password
test_S2_no_root_ssh
test_S3_allowgroups
test_S4_max_tries
test_S5_sshd_config_d
test_J1_fail2ban
test_J2_nftables
test_J3_journald_persistent
test_J4_analyse_logs_script
test_B1_sauvegarde_script
test_B2_cron_job
test_B3_backup_permissions
test_D1_unattended_upgrades
test_D2_listening_ports

TOTAL=$((REUSSIS + ECHECS))
echo "--------------------------------------------"
echo "Bilan : $REUSSIS / $TOTAL tests réussis."

if [ "$ECHECS" -eq 0 ]; then
    exit 0
else
    exit 1
fi