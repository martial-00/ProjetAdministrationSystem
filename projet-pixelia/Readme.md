# Projet XT1302-CYB — Durcissement d'un serveur Linux (Contexte A : Agence web Pixelia)

Ce dépôt contient l'ensemble des scripts d'automatisation, fichiers de configuration et outils de vérification permettant de déployer, sécuriser et auditer un serveur **Debian 13** minimal pour l'agence web **Pixelia**.

## 1. Contexte et architecture mise en place

Le projet répond au **Contexte A — Agence web Pixelia** du cahier des charges :

* **Comptes d'administration (`admins` + `acces_ssh`)** : `martial`, `gabriel`, `joao` (accès SSH par clé publique uniquement et droits `sudo` complets).
* **Compte de supervision (`support` + `acces_ssh`)** : `support` (accès SSH par clé publique et droit `sudo` strictement limité à `/usr/local/bin/analyse_logs.sh`).
* **Groupes métier (sans accès SSH)** :
  * `dev` (`dev1`, `dev2`)
  * `design` (`design1`, `design2`)
  * `commercial` (`com1`, `com2`)
  * `freelance` (`free1`, `free2`) — *expiration automatique fixée au `2026-12-31` et aucun accès `sudo`*.
* **Arborescence partagée `/srv` (permissions POSIX + ACL et ACL par défaut)** :
  * `/srv/projets` : `dev` (lecture/écriture), `design` (lecture), `freelance` (traversée uniquement pour accéder à `externe`).
  * `/srv/projets/externe` : `dev` (lecture/écriture), `design` (lecture), `freelance` (lecture/écriture).
  * `/srv/maquettes` : `design` (lecture/écriture), `dev` (lecture), `commercial` (lecture).
  * `/srv/clients` : `commercial` (lecture/écriture).

## 2. Structure du dépôt

```text
projet-pixelia/
├── README.md                                     # Documentation d'installation et d'utilisation
├── DOSSIER.md                                    # Dossier technique (conformité ANSSI, choix, défense, restauration)
├── comptes.csv                                   # Référentiel des utilisateurs et groupes
├── installer.sh                                  # Script principal de déploiement sur VM vierge
├── creer_comptes.sh                              # Création idempotente des comptes, groupes, clés SSH et ACL /srv
├── analyse_logs.sh                               # Analyse des journaux SSH et alerte sur seuil d'échecs
├── sauvegarde.sh                                 # Sauvegarde incrémentale (rsync --link-dest) avec rotation (7 versions)
├── verifier.sh                                   # Suite de tests automatisés validant toutes les exigences
└── config/
    ├── fail2ban/jail.d/sshd.conf                 # Protection anti-force brute SSH via nftables
    ├── journald.conf.d/10-persistent.conf        # Conservation persistante des journaux systemd
    ├── keys/                                     # Clés publiques SSH des comptes autorisés (acces_ssh)
    │   ├── gabriel.pub
    │   ├── joao.pub
    │   ├── martial.pub
    │   └── support.pub
    ├── nftables.conf                             # Pare-feu filtrant tout sauf SSH (TCP/22) et trafic établi
    ├── ssh/sshd_config.d/10-durcissement.conf    # Durcissement OpenSSH (clés uniquement, AllowGroups, timeouts)
    └── sudoers.d/
        ├── admins                                # Délégation sudo pour le groupe admins
        └── support                               # Restriction sudo de support à analyse_logs.sh
```

## 3. Prérequis

* **Machine virtuelle** : Debian 13 (installation minimale sans interface graphique, serveur OpenSSH installé).
* **Stockage** : un second disque virtuel (1 à 2 Go, ex. `/dev/sdb` ou `/dev/vdb`) attaché à la VM pour héberger `/mnt/sauvegardes`.
* **Réseau & accès** : accès `root` initial (avant verrouillage par `installer.sh`) et dépôts Debian officiels accessibles.
* **Poste client (hôte)** : disposer des clés privées correspondant aux clés publiques présentes dans `config/keys/`.

> **Recommandation :** Réalisez un **snapshot « vierge »** de la VM juste après l'installation de base afin de pouvoir tester la reconstruction complète à tout moment.

## 4. Installation et déploiement

1. **Cloner le dépôt sur la VM** (dans `/root`) :
   ```bash
   git clone https://github.com/martial-00/ProjetAdministrationSystem.git /root/ProjetAdministrationSystem
   ```

2. **Se placer dans le dossier du projet** :
   ```bash
   cd /root/ProjetAdministrationSystem/projet-pixelia
   ```

3. **Nettoyer les éventuelles fins de ligne Windows (`CRLF`), rendre `installer.sh` exécutable et lancer l'installation en `root`** :
   ```bash
   sed -i 's/\r$//' installer.sh && chmod +x installer.sh && ./installer.sh
   ```

### Ce que réalise `installer.sh` :
* Déplace le projet vers `/root/projet-pixelia` et normalise les fins de ligne (`CRLF` $\rightarrow$ `LF`) de l'ensemble des fichiers.
* Installe les paquets requis (`acl`, `openssh-server`, `fail2ban`, `nftables`, `unattended-upgrades`, `rsync`, `python3-systemd`) et active les mises à jour de sécurité automatiques (`D1`).
* Formate (uniquement si vierge) et monte le second disque sur `/mnt/sauvegardes` via `/etc/fstab` (`B1`, `B3`).
* Verrouille le compte `root` (`passwd -l root`) et restreint les droits des répertoires `/home/*` à `700` (`C4`).
* Déploie et valide les configurations `sudoers` (`visudo -c`), SSH (`sshd -t`), `fail2ban`, `nftables` et `journald` (`C3`, `S1`–`S5`, `J1`–`J3`).
* Copie les scripts dans `/usr/local/bin/` (`root:root`, `755`), exécute `creer_comptes.sh` (`C1`, `C2`) et planifie `sauvegarde.sh` tous les jours à `02h00` via `cron` (`B2`).

> **Attention :** Une fois `installer.sh` exécuté, `root` est verrouillé et l'authentification SSH par mot de passe est désactivée. Conservez une session ouverte ou testez immédiatement la connexion SSH avec une clé administrateur (`ssh -i <cle_privee> martial@<IP_VM>`) avant de fermer votre session courante.

## 5. Vérification et exploitation courante

### Exécuter l'audit automatique (`verifier.sh`)
Depuis `/root/projet-pixelia` (en `root` ou via `sudo`) :
```bash
cd /root/projet-pixelia
chmod +x verifier.sh
sudo ./verifier.sh
```
Le script teste automatiquement chaque exigence du cahier des charges (`C1`–`C4`, `S1`–`S5`, `J1`–`J4`, `B1`–`B4`, `D1`–`D3`) et retourne `0` si tout est conforme, ou `1` en cas d'anomalie.

### Analyser les connexions SSH (`analyse_logs.sh`)
Utilisable par les administrateurs ou par le compte `support` (seul droit `sudo` autorisé) :
```bash
sudo /usr/local/bin/analyse_logs.sh        # Seuil d'alerte par défaut : 5 échecs
sudo /usr/local/bin/analyse_logs.sh 3      # Seuil personnalisé : 3 échecs
```

### Lancer une sauvegarde manuelle (`sauvegarde.sh`)
```bash
sudo /usr/local/bin/sauvegarde.sh
```
Les sauvegardes incrémentales de `/srv` et `/etc` sont stockées dans `/mnt/sauvegardes/backup-YYYY-MM-DD_HHMMSS` (avec rétention des 7 dernières versions et journalisation dans `/var/log/sauvegarde.log`).

### Débannir une IP bloquée par Fail2ban (tests de force brute)
```bash
sudo fail2ban-client set sshd unbanip <IP_CLIENT>
```

## 6. Équipe projet

* **Contexte** : Contexte A — Agence web Pixelia
* **Membres du groupe** : Martial, Gabriel, Joao