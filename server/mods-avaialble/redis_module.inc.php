<?php
// /usr/local/ispconfig/server/mods-available/redis_module.inc.php

class redis_module {
    var $module_name = 'redis_module';
    var $class_name = 'redis_module';
    var $actions_available = array(
        'redis_instances_insert',
        'redis_instances_update', 
        'redis_instances_delete'
    );
    
    function onInstall() {
        global $app;
        
        // Redis-Verzeichnisse erstellen
        if (!is_dir('/etc/redis')) {
            mkdir('/etc/redis', 0755, true);
        }
        if (!is_dir('/var/lib/redis')) {
            mkdir('/var/lib/redis', 0755, true);
            chown('/var/lib/redis', 'redis');
            chgrp('/var/lib/redis', 'redis');
        }
        if (!is_dir('/var/log/redis')) {
            mkdir('/var/log/redis', 0755, true);
            chown('/var/log/redis', 'redis');
            chgrp('/var/log/redis', 'redis');
        }
        
        return true;
    }
    
    function onLoad() {
        global $app;
        
        $app->modules->registerEvent('redis_instances_insert', $this->module_name, 'redis_insert');
        $app->modules->registerEvent('redis_instances_update', $this->module_name, 'redis_update');  
        $app->modules->registerEvent('redis_instances_delete', $this->module_name, 'redis_delete');
    }
    
    function redis_insert($event_name, $data) {
        global $app, $conf;
        
        if($data['new']['server_id'] != $conf['server_id']) return;
        
        $redis_data = $data['new'];
        $this->createRedisInstance($redis_data);
    }
    
    function redis_update($event_name, $data) {
        global $app, $conf;
        
        if($data['new']['server_id'] != $conf['server_id']) return;
        
        $redis_data = $data['new'];
        $this->updateRedisInstance($redis_data);
    }
    
    function redis_delete($event_name, $data) {
        global $app, $conf;
        
        if($data['old']['server_id'] != $conf['server_id']) return;
        
        $redis_data = $data['old'];
        $this->deleteRedisInstance($redis_data);
    }
    
    private function createRedisInstance($data) {
        global $app;
        
        $redis_name = $data['redis_name'];
        
        // Instanz-Verzeichnis erstellen
        $instance_dir = "/var/lib/redis/{$redis_name}";
        if (!is_dir($instance_dir)) {
            mkdir($instance_dir, 0750, true);
            chown($instance_dir, 'redis');
            chgrp($instance_dir, 'redis');
        }
        
        // Konfigurationsdatei erstellen
        $config_content = $this->generateConfig($data);
        $config_file = "/etc/redis/redis-{$redis_name}.conf";
        
        file_put_contents($config_file, $config_content);
        chown($config_file, 'redis');
        chgrp($config_file, 'redis');
        chmod($config_file, 0640);
        
        // Systemd Service erstellen
        $this->createSystemdService($redis_name, $data['redis_port']);
        
        // Service starten falls aktiv
        if ($data['active'] == 'y') {
            exec("systemctl enable redis-{$redis_name}.service 2>&1", $output, $return_code);
            exec("systemctl start redis-{$redis_name}.service 2>&1", $output, $return_code);
            
            if ($return_code == 0) {
                $app->log("Redis instance {$redis_name} started successfully", LOGLEVEL_DEBUG);
            } else {
                $app->log("Failed to start Redis instance {$redis_name}: " . implode("\n", $output), LOGLEVEL_ERROR);
            }
        }
    }
    
    private function updateRedisInstance($data) {
        global $app;
        
        $redis_name = $data['redis_name'];
        
        // Konfiguration aktualisieren
        $config_content = $this->generateConfig($data);
        $config_file = "/etc/redis/redis-{$redis_name}.conf";
        
        file_put_contents($config_file, $config_content);
        
        // Service Status prüfen und entsprechend handeln
        if ($data['active'] == 'y') {
            exec("systemctl is-active redis-{$redis_name}.service", $output, $return_code);
            
            if ($return_code == 0) {
                // Service läuft, neu starten
                exec("systemctl restart redis-{$redis_name}.service");
            } else {
                // Service läuft nicht, starten
                exec("systemctl enable redis-{$redis_name}.service");
                exec("systemctl start redis-{$redis_name}.service");
            }
        } else {
            // Service stoppen falls läuft
            exec("systemctl stop redis-{$redis_name}.service");
            exec("systemctl disable redis-{$redis_name}.service");
        }
        
        $app->log("Redis instance {$redis_name} updated", LOGLEVEL_DEBUG);
    }
    
    private function deleteRedisInstance($data) {
        global $app;
        
        $redis_name = $data['redis_name'];
        
        // Service stoppen und deaktivieren
        exec("systemctl stop redis-{$redis_name}.service 2>/dev/null");
        exec("systemctl disable redis-{$redis_name}.service 2>/dev/null");
        
        // Service-Datei löschen
        $service_file = "/etc/systemd/system/redis-{$redis_name}.service";
        if (file_exists($service_file)) {
            unlink($service_file);
        }
        
        // Konfigurationsdatei löschen
        $config_file = "/etc/redis/redis-{$redis_name}.conf";
        if (file_exists($config_file)) {
            unlink($config_file);
        }
        
        // Datenverzeichnis löschen (optional, könnte auch archiviert werden)
        $instance_dir = "/var/lib/redis/{$redis_name}";
        if (is_dir($instance_dir)) {
            exec("rm -rf " . escapeshellarg($instance_dir));
        }
        
        // Systemd reload
        exec("systemctl daemon-reload");
        
        $app->log("Redis instance {$redis_name} deleted", LOGLEVEL_DEBUG);
    }
    
    private function generateConfig($data) {
        $redis_config = new RedisConfig();
        return $redis_config->generateConfigFromTemplate($data);
    }
    
    private function createSystemdService($instance_name, $port) {
        $service_content = "[Unit]
Description=Redis In-Memory Data Store (Instance: {$instance_name})
After=network.target

[Service]
Type=notify
User=redis
Group=redis
ExecStart=/usr/bin/redis-server /etc/redis/redis-{$instance_name}.conf
ExecStop=/bin/kill -s QUIT \$MAINPID
TimeoutStopSec=0
Restart=always
RestartSec=5

# Security
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/var/lib/redis/{$instance_name}
ReadWritePaths=/var/log/redis

[Install]
WantedBy=multi-user.target";

        file_put_contents("/etc/systemd/system/redis-{$instance_name}.service", $service_content);
        exec("systemctl daemon-reload");
    }
}
?>