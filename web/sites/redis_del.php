<?php
// /usr/local/ispconfig/interface/web/sites/redis_del.php

require_once '../../lib/config.inc.php';
require_once '../../lib/app.inc.php';

$app->auth->check_module_permissions('sites');
$app->uses('tpl,tform');
$app->load('tform_actions');

class page_action extends tform_actions {
    
    function onBeforeDelete() {
        global $app;
        
        $redis_id = intval($_GET['id']);
        $sql = "SELECT * FROM redis_instances WHERE redis_id = ?";
        
        if($_SESSION["s"]["user"]["typ"] != 'admin') {
            $sql .= " AND client_id = " . intval($_SESSION["s"]["user"]["client_id"]);
        }
        
        $redis_record = $app->db->queryOneRecord($sql, $redis_id);
        
        if(!$redis_record) {
            $app->error('No permission or record not found');
        }
        
        // Prüfe ob Redis-Instanz von anderen Services verwendet wird
        // (Hier könnten weitere Checks implementiert werden)
        
        return true;
    }
    
    function onAfterDelete() {
        global $app;
        $app->tform->showMsg($app->lng('redis_deleted_txt'));
    }
}

// Formular-Definition laden
$app->tform->loadFormDef('redis_instances.tform.php');

$page = new page_action;
$page->onLoad();
?>