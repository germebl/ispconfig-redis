<?php
// /usr/local/ispconfig/interface/web/sites/redis_list.php

require_once '../../lib/config.inc.php'; 
require_once '../../lib/app.inc.php';

$app->auth->check_module_permissions('sites');
$app->auth->check_security_permissions('admin_allow_server_redis');

$app->uses('tpl,tform,paging');
$app->load('tform_actions');

class page_action extends tform_actions {
    function onShow() {
        global $app;
        
        $sql = "SELECT * FROM redis_instances WHERE client_id = ?";
        if($_SESSION["s"]["user"]["typ"] == 'admin') {
            $sql = "SELECT r.*, c.company_name, s.server_name 
                    FROM redis_instances r 
                    LEFT JOIN client c ON r.client_id = c.client_id 
                    LEFT JOIN server s ON r.server_id = s.server_id";
            $records = $app->db->queryAllRecords($sql);
        } else {
            $records = $app->db->queryAllRecords($sql, $_SESSION["s"]["user"]["client_id"]);
        }
        
        $app->tpl->setLoop('records', $records);
    }
}

$page = new page_action;
$page->onShow();
?>