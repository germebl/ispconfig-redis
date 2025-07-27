-- Redis Instanzen Tabelle
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

-- Redis Konfigurationsvorlagen
CREATE TABLE `redis_config_templates` (
  `template_id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `template_name` varchar(255) NOT NULL,
  `template_config` text NOT NULL,
  `description` text,
  PRIMARY KEY (`template_id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;