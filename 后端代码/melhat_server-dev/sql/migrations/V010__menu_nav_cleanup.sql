-- S10 follow-up: put live workflow first; park old hat pages under 旧版功能.
-- Routes stay; this is navigation only. Not a cutover.

SET @business_menu_id := (SELECT menu_id FROM sys_menu WHERE parent_id = 0 AND path = 'business' AND menu_type = 'M' LIMIT 1);

UPDATE sys_menu SET order_num = 1, update_by = 'demo', update_time = NOW()
 WHERE parent_id = 0 AND path = 'business';
UPDATE sys_menu SET order_num = 8, update_by = 'demo', update_time = NOW()
 WHERE parent_id = 0 AND path = 'system';
UPDATE sys_menu SET visible = '1', order_num = 9, update_by = 'demo', update_time = NOW()
 WHERE parent_id = 0 AND path = 'secure';

UPDATE sys_menu SET order_num = 1, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'duty';
UPDATE sys_menu SET order_num = 2, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'events';
UPDATE sys_menu SET order_num = 3, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'work-tasks';
UPDATE sys_menu SET order_num = 4, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'locations';
UPDATE sys_menu SET order_num = 5, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'geo-fences';
UPDATE sys_menu SET order_num = 10, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'people';
UPDATE sys_menu SET order_num = 11, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'devices';
UPDATE sys_menu SET order_num = 12, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'spaces';

INSERT INTO sys_menu (menu_name, parent_id, order_num, path, component, query, is_frame, is_cache, menu_type, visible, status, perms, icon, create_by, create_time, remark)
SELECT '旧版功能', @business_menu_id, 90, 'legacy', NULL, '', 1, 0, 'M', '0', '0', '', 'time-range', 'demo', NOW(),
       '旧帽页回查，不是本平台真相'
 WHERE @business_menu_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'legacy' AND menu_type = 'M');

SET @legacy_menu_id := (SELECT menu_id FROM sys_menu WHERE parent_id = @business_menu_id AND path = 'legacy' AND menu_type = 'M' LIMIT 1);

UPDATE sys_menu SET parent_id = @legacy_menu_id, order_num = 1, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'group' AND @legacy_menu_id IS NOT NULL;
UPDATE sys_menu SET parent_id = @legacy_menu_id, order_num = 2, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'hat' AND @legacy_menu_id IS NOT NULL;
UPDATE sys_menu SET parent_id = @legacy_menu_id, order_num = 3, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'live' AND @legacy_menu_id IS NOT NULL;
UPDATE sys_menu SET parent_id = @legacy_menu_id, order_num = 4, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'track' AND @legacy_menu_id IS NOT NULL;
UPDATE sys_menu SET parent_id = @legacy_menu_id, order_num = 5, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'fence' AND @legacy_menu_id IS NOT NULL;
UPDATE sys_menu SET parent_id = @legacy_menu_id, order_num = 6, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'sos' AND @legacy_menu_id IS NOT NULL;
UPDATE sys_menu SET parent_id = @legacy_menu_id, order_num = 7, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'file' AND @legacy_menu_id IS NOT NULL;
UPDATE sys_menu SET parent_id = @legacy_menu_id, order_num = 8, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'intercom' AND @legacy_menu_id IS NOT NULL;
UPDATE sys_menu SET parent_id = @legacy_menu_id, order_num = 9, update_by = 'demo', update_time = NOW()
 WHERE parent_id = @business_menu_id AND path = 'tts' AND @legacy_menu_id IS NOT NULL;

INSERT IGNORE INTO sys_role_menu (role_id, menu_id)
SELECT r.role_id, @legacy_menu_id
  FROM sys_role r
 WHERE @legacy_menu_id IS NOT NULL
   AND r.role_key IN ('wear_platform_admin','wear_device_admin','admin');

DELETE rm
  FROM sys_role_menu rm
  JOIN sys_role r ON r.role_id = rm.role_id
  JOIN sys_menu m ON m.menu_id = rm.menu_id
 WHERE r.role_key IN ('wear_duty','wear_readonly','wear_reviewer','wear_team_lead')
   AND (
        m.path IN ('group','hat','live','track','fence','sos','file','intercom','tts','legacy')
     OR (m.parent_id = @legacy_menu_id)
   );
