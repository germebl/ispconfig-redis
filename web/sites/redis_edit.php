<?php
// /usr/local/ispconfig/interface/web/sites/redis_edit.php

require_once '../../lib/config.inc.php';
require_once '../../lib/app.inc.php';

$app->auth->check_module_permissions('sites');
$app->uses('tpl,tform,validate');
$app->load('tform_actions');

class page_action extends tform_actions {
    
    function onShowNew() {
        global $app, $conf;
        
        // Standardwerte setzen
        $this->dataRecord['redis_maxmemory'] = '128mb';
        $this->dataRecord['redis_optimization_mode'] = 'cache';
        $this->dataRecord['redis_maxmemory_policy'] = 'allkeys-lru';
        $this->dataRecord['redis_bind'] = '127.0.0.1';
        $this->dataRecord['active'] = 'y';
        
        parent::onShowNew();
    }
    
    function onShowEdit() {
        global $app;
        
        // Redis-Instanz laden
        $redis_id = intval($_GET['id']);
        $sql = "SELECT * FROM redis_instances WHERE redis_id = ?";
        
        if($_SESSION["s"]["user"]["typ"] != 'admin') {
            $sql .= " AND client_id = " . intval($_SESSION["s"]["user"]["client_id"]);
        }
        
        $this->dataRecord = $app->db->queryOneRecord($sql, $redis_id);
        
        if(!$this->dataRecord) {
            $app->error('No permission or record not found');
        }
        
        parent::onShowEdit();
    }
    
    function onSubmit() {
        global $app;
        
        // Validierung
        $redis_config = new RedisConfig();
        $errors = $redis_config->validateConfig($this->dataRecord);
        
        if (!empty($errors)) {
            foreach ($errors as $error) {
                $app->tform->errorMessage .= $error . '<br>';
            }
            return;
        }
        
        // Prüfe ob Name bereits existiert (bei neuen Instanzen)
        if ($this->id == 0) {
            $sql = "SELECT redis_id FROM redis_instances WHERE redis_name = ? AND server_id = ?";
            $existing = $app->db->queryOneRecord($sql, $this->dataRecord['redis_name'], $this->dataRecord['server_id']);
            
            if ($existing) {
                $app->tform->errorMessage .= $app->lng('error_redis_name_exists') . '<br>';
                return;
            }
        }
        
        // Server ID setzen falls nicht admin
        if($_SESSION["s"]["user"]["typ"] != 'admin') {
            $this->dataRecord['server_id'] = intval($app->functions->getClientDefaultServer($_SESSION["s"]["user"]["client_id"]));
            $this->dataRecord['client_id'] = intval($_SESSION["s"]["user"]["client_id"]);
        }
        
        parent::onSubmit();
    }
    
    function onAfterInsert() {
        global $app;
        
        // Port zuweisen falls nicht gesetzt
        if (empty($this->dataRecord['redis_port'])) {
            $redis_manager = new RedisManager();
            $port = $redis_manager->getNextAvailablePort($this->dataRecord['server_id']);
            
            $sql = "UPDATE redis_instances SET redis_port = ? WHERE redis_id = ?";
            $app->db->query($sql, $port, $this->id);
        }
        
        $app->tform->showMsg($app->lng('redis_created_txt'));
    }
    
    function onAfterUpdate() {
        global $app;
        $app->tform->showMsg($app->lng('redis_updated_txt'));
    }
}

// Formular-Definition laden
$app->tform->loadFormDef('redis_instances.tform.php');

$page = new page_action;
$page->onLoad();
?>