<?php
// /usr/local/ispconfig/server/plugins-available/redis_plugin.inc.php

class redis_plugin {
    var $plugin_name = 'redis_plugin';
    var $class_name = 'redis_plugin';
    
    function onInstall() {
        global $app;
        return true;
    }
    
    function onLoad() {
        global $app;
        
        $app->plugins->registerEvent('redis_instances_insert', $this->plugin_name, 'redis_insert');
        $app->plugins->registerEvent('redis_instances_update', $this->plugin_name, 'redis_update');
        $app->plugins->registerEvent('redis_instances_delete', $this->plugin_name, 'redis_delete');
    }
    
    function redis_insert($event_name, $data) {
        global $app;
        
        $redis_data = $data['new'];
        
        // Redis-Konfigurationsdatei erstellen
        $config_file = "/etc/redis/redis-{$redis_data['redis_name']}.conf";
        $config_content = $this->generateRedisConfig($redis_data);
        
        file_put_contents($config_file, $config_content);
        chown($config_file, 'redis');
        chgrp($config_file, 'redis');
        chmod($config_file, 0640);
        
        // Service starten
        exec("systemctl start redis-{$redis_data['redis_name']}.service");
        
        $app->log("Redis instance {$redis_data['redis_name']} created and started", LOGLEVEL_DEBUG);
    }
    
    function redis_update($event_name, $data) {
        global $app;
        
        $redis_data = $data['new'];
        
        // Konfiguration aktualisieren
        $config_file = "/etc/redis/redis-{$redis_data['redis_name']}.conf";
        $config_content = $this->generateRedisConfig($redis_data);
        
        file_put_contents($config_file, $config_content);
        
        // Service neu starten
        exec("systemctl restart redis-{$redis_data['redis_name']}.service");
        
        $app->log("Redis instance {$redis_data['redis_name']} updated", LOGLEVEL_DEBUG);
    }
    
    function redis_delete($event_name, $data) {
        global $app;
        
        $redis_data = $data['old'];
        
        // Service stoppen und deaktivieren
        exec("systemctl stop redis-{$redis_data['redis_name']}.service");
        exec("systemctl disable redis-{$redis_data['redis_name']}.service");
        
        // Dateien löschen
        unlink("/etc/redis/redis-{$redis_data['redis_name']}.conf");
        unlink("/etc/systemd/system/redis-{$redis_data['redis_name']}.service");
        
        // Systemd reload
        exec("systemctl daemon-reload");
        
        $app->log("Redis instance {$redis_data['redis_name']} deleted", LOGLEVEL_DEBUG);
    }
    
    private function generateRedisConfig($data) {
        // Ähnlich wie in RedisManager::generateConfig()
        // ... (Konfiguration generieren basierend auf $data)
    }
}
?>