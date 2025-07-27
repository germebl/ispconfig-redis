#!/bin/bash
# Redis Plugin Installer für ISPConfig 3.3

set -e

echo "ISPConfig Redis Plugin Installer"
echo "================================="

# Prüfe ob als root ausgeführt
if [[ $EUID -ne 0 ]]; then
   echo "Fehler: Dieses Script muss als root ausgeführt werden"
   exit 1
fi

# Prüfe ob ISPConfig installiert ist
if [ ! -f "/usr/local/ispconfig/server/lib/mysql_clientdb.conf" ]; then
    echo "Fehler: ISPConfig nicht gefunden"
    exit 1
fi

echo "1. Git installieren (falls nicht vorhanden)..."
if ! command -v git &> /dev/null; then
    apt update
    apt install -y git
    echo "   Git installiert"
else
    echo "   Git bereits installiert"
fi

echo "2. Redis Server installieren..."
if ! command -v redis-server &> /dev/null; then
    apt update
    apt install -y redis-server redis-tools
    echo "   Redis Server installiert"
else
    echo "   Redis Server bereits installiert"
fi

# Redis Service stoppen (wir verwalten Instanzen selbst)
systemctl stop redis-server 2>/dev/null || true
systemctl disable redis-server 2>/dev/null || true

echo "3. Plugin-Code von GitHub herunterladen..."

# Temporäres Verzeichnis erstellen
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Repository klonen
git clone git@github.com:germebl/ispconfig_redis.git
cd ispconfig_redis

if [ ! -d "." ]; then
    echo "Fehler: Plugin-Repository konnte nicht geklont werden"
    exit 1
fi

echo "4. Redis-Benutzer und Verzeichnisse einrichten..."

# Redis-Benutzer erstellen falls nicht vorhanden
if ! id redis &>/dev/null; then
    useradd -r -s /bin/false redis
    echo "   Redis-Benutzer erstellt"
else
    echo "   Redis-Benutzer bereits vorhanden"
fi

# Verzeichnisse erstellen
mkdir -p /etc/redis
mkdir -p /var/lib/redis
mkdir -p /var/log/redis
mkdir -p /var/run/redis

chown redis:redis /var/lib/redis
chown redis:redis /var/log/redis
chown redis:redis /var/run/redis
chmod 750 /var/lib/redis
chmod 750 /var/log/redis
chmod 755 /var/run/redis

echo "5. MySQL-Verbindungsdaten extrahieren..."

# MySQL-Konfiguration lesen
MYSQL_CONFIG="/usr/local/ispconfig/server/lib/mysql_clientdb.conf"

# Extrahiere Werte mit awk (robuster als cut)
DB_PASSWORD=$(grep "clientdb_password" "$MYSQL_CONFIG" | awk -F"'" '{print $2}')
DB_USER=$(grep "clientdb_user" "$MYSQL_CONFIG" | awk -F"'" '{print $2}')
DB_NAME=$(grep "clientdb_database" "$MYSQL_CONFIG" | awk -F"'" '{print $2}')
DB_HOST=$(grep "clientdb_host" "$MYSQL_CONFIG" | awk -F"'" '{print $2}')

# Fallback-Werte falls nicht gefunden
DB_USER=${DB_USER:-"ispconfig"}
DB_HOST=${DB_HOST:-"localhost"}
DB_NAME=${DB_NAME:-"dbispconfig"}

echo "   Database: $DB_NAME"
echo "   User: $DB_USER"
echo "   Host: $DB_HOST"

if [ -z "$DB_PASSWORD" ]; then
    echo "Fehler: Konnte MySQL-Passwort nicht extrahieren"
    echo "Bitte prüfen Sie die Datei: $MYSQL_CONFIG"
    exit 1
fi

echo "6. Datenbank-Schema prüfen und installieren..."

# Prüfe ob Redis-Tabellen bereits existieren
check_table_exists() {
    local table_name=$1
    mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
        -e "SHOW TABLES LIKE '$table_name';" 2>/dev/null | grep -q "$table_name"
}

# Prüfe ob Tabellen-Struktur korrekt ist
check_table_structure() {
    local table_name=$1
    case $table_name in
        "redis_instances")
            # Prüfe ob alle erforderlichen Spalten vorhanden sind
            local required_columns=("redis_id" "redis_name" "redis_port" "redis_maxmemory" "redis_optimization_mode" "server_id" "client_id" "active")
            for column in "${required_columns[@]}"; do
                if ! mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
                    -e "SHOW COLUMNS FROM $table_name LIKE '$column';" 2>/dev/null | grep -q "$column"; then
                    return 1
                fi
            done
            return 0
            ;;
        "redis_config_templates")
            local required_columns=("template_id" "template_name" "template_config")
            for column in "${required_columns[@]}"; do
                if ! mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
                    -e "SHOW COLUMNS FROM $table_name LIKE '$column';" 2>/dev/null | grep -q "$column"; then
                    return 1
                fi
            done
            return 0
            ;;
    esac
    return 1
}

# Prüfe redis_instances Tabelle
if check_table_exists "redis_instances"; then
    if check_table_structure "redis_instances"; then
        echo "   Tabelle 'redis_instances' ist bereits korrekt vorhanden"
    else
        echo "   Warnung: Tabelle 'redis_instances' existiert, aber Struktur ist nicht korrekt"
        echo "   Möchten Sie die Tabelle aktualisieren? (j/n)"
        read -r response
        if [[ "$response" =~ ^[Jj]$ ]]; then
            # Backup erstellen
            mysqldump -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" redis_instances > "/tmp/redis_instances_backup_$(date +%Y%m%d_%H%M%S).sql"
            echo "   Backup erstellt: /tmp/redis_instances_backup_$(date +%Y%m%d_%H%M%S).sql"
            
            # Tabelle löschen und neu erstellen
            mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "DROP TABLE redis_instances;"
            mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "install/sql/redis_tables.sql"
            echo "   Tabelle 'redis_instances' aktualisiert"
        else
            echo "   Installation abgebrochen"
            exit 1
        fi
    fi
else
    echo "   Erstelle Tabelle 'redis_instances'..."
    # Nur redis_instances Tabelle erstellen
    mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" << 'EOF'
CREATE TABLE `redis_instances` (
  `redis_id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `sys_userid` int(11) unsigned NOT NULL DEFAULT '0',
  `sys_groupid` int(11) unsigned NOT NULL DEFAULT '0',
  `sys_perm_user` varchar(5) DEFAULT NULL,
  `sys_perm_group` varchar(5) DEFAULT NULL,
  `sys_perm_other` varchar(5) DEFAULT NULL,
  `server_id` int(11) unsigned NOT NULL DEFAULT '0',
  `client_id` int(11) unsigned NOT NULL DEFAULT '0',
  `redis_name` varchar(255) NOT NULL DEFAULT '',
  `redis_port` int(5) unsigned NOT NULL DEFAULT '6379',
  `redis_bind` varchar(255) NOT NULL DEFAULT '127.0.0.1',
  `redis_password` varchar(255) DEFAULT NULL,
  `redis_maxmemory` varchar(20) NOT NULL DEFAULT '128mb',
  `redis_maxmemory_policy` enum('noeviction','allkeys-lru','volatile-lru','allkeys-random','volatile-random','volatile-ttl','volatile-lfu','allkeys-lfu') NOT NULL DEFAULT 'allkeys-lru',
  `redis_optimization_mode` enum('cache','fullpage','session','custom') NOT NULL DEFAULT 'cache',
  `redis_save_policy` varchar(255) DEFAULT '900 1 300 10 60 10000',
  `redis_appendonly` enum('yes','no') NOT NULL DEFAULT 'no',
  `redis_custom_config` text,
  `active` enum('y','n') NOT NULL DEFAULT 'y',
  PRIMARY KEY (`redis_id`),
  KEY `server_id` (`server_id`),
  KEY `client_id` (`client_id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
EOF
    echo "   Tabelle 'redis_instances' erstellt"
fi

# Prüfe redis_config_templates Tabelle
if check_table_exists "redis_config_templates"; then
    if check_table_structure "redis_config_templates"; then
        echo "   Tabelle 'redis_config_templates' ist bereits korrekt vorhanden"
    else
        echo "   Warnung: Tabelle 'redis_config_templates' existiert, aber Struktur ist nicht korrekt"
        echo "   Möchten Sie die Tabelle aktualisieren? (j/n)"
        read -r response
        if [[ "$response" =~ ^[Jj]$ ]]; then
            # Backup erstellen
            mysqldump -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" redis_config_templates > "/tmp/redis_config_templates_backup_$(date +%Y%m%d_%H%M%S).sql"
            echo "   Backup erstellt: /tmp/redis_config_templates_backup_$(date +%Y%m%d_%H%M%S).sql"
            
            # Tabelle löschen und neu erstellen
            mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "DROP TABLE redis_config_templates;"
            mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" << 'EOF'
CREATE TABLE `redis_config_templates` (
  `template_id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `template_name` varchar(255) NOT NULL,
  `template_config` text NOT NULL,
  `description` text,
  PRIMARY KEY (`template_id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
EOF
            echo "   Tabelle 'redis_config_templates' aktualisiert"
        else
            echo "   Installation abgebrochen"
            exit 1
        fi
    fi
else
    echo "   Erstelle Tabelle 'redis_config_templates'..."
    mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" << 'EOF'
CREATE TABLE `redis_config_templates` (
  `template_id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `template_name` varchar(255) NOT NULL,
  `template_config` text NOT NULL,
  `description` text,
  PRIMARY KEY (`template_id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
EOF
    echo "   Tabelle 'redis_config_templates' erstellt"
fi

echo "7. Plugin-Dateien kopieren..."

# Plugin-Dateien kopieren
mkdir -p /usr/local/ispconfig/interface/plugins/redis/
cp -r lib/ /usr/local/ispconfig/interface/plugins/redis/
cp -r web/ /usr/local/ispconfig/interface/plugins/redis/
cp -r install/ /usr/local/ispconfig/interface/plugins/redis/

mkdir -p /usr/local/ispconfig/server/plugins-available/
mkdir -p /usr/local/ispconfig/server/mods-available/
cp server/plugins-available/* /usr/local/ispconfig/server/plugins-available/ 2>/dev/null || true
cp server/mods-available/* /usr/local/ispconfig/server/mods-available/ 2>/dev/null || true

# Berechtigungen setzen
chown -R ispconfig:ispconfig /usr/local/ispconfig/interface/plugins/redis/
chmod -R 644 /usr/local/ispconfig/interface/plugins/redis/
find /usr/local/ispconfig/interface/plugins/redis/ -type d -exec chmod 755 {} \;

echo "8. ISPConfig-Module aktivieren..."

# Plugin in ISPConfig aktivieren
mkdir -p /usr/local/ispconfig/server/plugins-enabled/
mkdir -p /usr/local/ispconfig/server/mods-enabled/

if [ -f "/usr/local/ispconfig/server/plugins-available/redis_plugin.inc.php" ]; then
    ln -sf /usr/local/ispconfig/server/plugins-available/redis_plugin.inc.php \
           /usr/local/ispconfig/server/plugins-enabled/redis_plugin.inc.php
    echo "   Redis Plugin aktiviert"
fi

if [ -f "/usr/local/ispconfig/server/mods-available/redis_module.inc.php" ]; then
    ln -sf /usr/local/ispconfig/server/mods-available/redis_module.inc.php \
           /usr/local/ispconfig/server/mods-enabled/redis_module.inc.php
    echo "   Redis Modul aktiviert"
fi

echo "9. Berechtigungen in ISPConfig hinzufügen..."

# Berechtigungen zur Datenbank hinzufügen
mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" << 'EOF'
INSERT IGNORE INTO sys_user_modules (module, description) VALUES 
('redis', 'Redis Instances Management');

INSERT IGNORE INTO sys_user_permissions (module, function, description) VALUES
('redis', 'redis_instances', 'Redis Instances'),
('redis', 'redis_instances_view', 'View Redis Instances'),
('redis', 'redis_instances_add', 'Add Redis Instances'),
('redis', 'redis_instances_edit', 'Edit Redis Instances'),
('redis', 'redis_instances_delete', 'Delete Redis Instances');
EOF

echo "10. ISPConfig neustarten..."

# Apache/Nginx neustarten je nach Setup
if systemctl is-active --quiet apache2; then
    systemctl restart apache2
    echo "   Apache2 neugestartet"
elif systemctl is-active --quiet nginx; then
    systemctl restart nginx
    echo "   Nginx neugestartet"
fi

# ISPConfig Server neustarten
systemctl restart ispconfig_server
echo "   ISPConfig Server neugestartet"

echo "11. Aufräumen..."

# Temporäres Verzeichnis löschen
cd /
rm -rf "$TEMP_DIR"

echo ""
echo "==============================================="
echo "Redis Plugin erfolgreich installiert!"
echo "==============================================="
echo ""
echo "Das Plugin ist jetzt verfügbar unter:"
echo "ISPConfig Panel > Sites > Redis Instances"
echo ""
echo "Repository: git@github.com:germebl/ispconfig_redis.git"
echo ""
echo "Hinweise:"
echo "- Stellen Sie sicher, dass die Firewall die Redis-Ports freigibt"
echo "- Redis-Instanzen laufen standardmäßig nur auf localhost (127.0.0.1)"
echo "- Jede Instanz erhält automatisch einen eigenen Port (ab 6379)"
echo ""
echo "Log-Dateien:"
echo "- ISPConfig: /var/log/ispconfig/ispconfig.log"
echo "- Redis Instanzen: /var/log/redis/"
echo ""

# Zeige nächste verfügbaren Port
NEXT_PORT=$(mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -sN \
    -e "SELECT COALESCE(MAX(redis_port), 6378) + 1 FROM redis_instances;" 2>/dev/null || echo "6379")
echo "Nächster verfügbarer Port: $NEXT_PORT"