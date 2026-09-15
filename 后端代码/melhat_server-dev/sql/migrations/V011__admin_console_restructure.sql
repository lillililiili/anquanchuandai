-- PC 后台管理系统信息架构重组。幂等执行，不删除业务数据。

INSERT INTO sys_menu (menu_name,parent_id,order_num,path,component,query,is_frame,is_cache,menu_type,visible,status,perms,icon,create_by,create_time,remark)
SELECT '管理概览',0,1,'dashboard','dashboard/index','',1,0,'C','0','0','wear:overview:list','dashboard','admin',NOW(),'PC 管理与审计概览'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id=0 AND path='dashboard');

INSERT INTO sys_menu (menu_name,parent_id,order_num,path,component,query,is_frame,is_cache,menu_type,visible,status,perms,icon,create_by,create_time,remark)
SELECT '基础资料',0,2,'master-data',NULL,'',1,0,'M','0','0','','tree-table','admin',NOW(),'人员和组织基础资料'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id=0 AND path='master-data');
INSERT INTO sys_menu (menu_name,parent_id,order_num,path,component,query,is_frame,is_cache,menu_type,visible,status,perms,icon,create_by,create_time,remark)
SELECT '设备资产',0,3,'assets',NULL,'',1,0,'M','0','0','','build','admin',NOW(),'设备型号和领用归还'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id=0 AND path='assets');
INSERT INTO sys_menu (menu_name,parent_id,order_num,path,component,query,is_frame,is_cache,menu_type,visible,status,perms,icon,create_by,create_time,remark)
SELECT '作业配置',0,4,'work',NULL,'',1,0,'M','0','0','','form','admin',NOW(),'任务和电子围栏配置'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id=0 AND path='work');
INSERT INTO sys_menu (menu_name,parent_id,order_num,path,component,query,is_frame,is_cache,menu_type,visible,status,perms,icon,create_by,create_time,remark)
SELECT '安全审计',0,5,'audit',NULL,'',1,0,'M','0','0','','documentation','admin',NOW(),'事件与文件只读审计'
WHERE NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id=0 AND path='audit');

SET @master_id := (SELECT menu_id FROM sys_menu WHERE parent_id=0 AND path='master-data' LIMIT 1);
SET @assets_id := (SELECT menu_id FROM sys_menu WHERE parent_id=0 AND path='assets' LIMIT 1);
SET @work_id := (SELECT menu_id FROM sys_menu WHERE parent_id=0 AND path='work' LIMIT 1);
SET @audit_id := (SELECT menu_id FROM sys_menu WHERE parent_id=0 AND path='audit' LIMIT 1);

UPDATE sys_menu SET parent_id=@master_id,order_num=1,path='people',component='people/index',menu_name='人员台账',visible='0',status='0',update_by='admin',update_time=NOW()
WHERE path='people' AND menu_type='C' LIMIT 1;
UPDATE sys_menu SET parent_id=@master_id,order_num=3,path='spaces',component='spaces/index',menu_name='区域资料',visible='0',status='0',update_by='admin',update_time=NOW()
WHERE path='spaces' AND menu_type='C' LIMIT 1;
UPDATE sys_menu SET parent_id=@assets_id,order_num=1,path='devices',component='devices/index',menu_name='设备台账',visible='0',status='0',update_by='admin',update_time=NOW()
WHERE path='devices' AND menu_type='C' LIMIT 1;
UPDATE sys_menu SET parent_id=@work_id,order_num=1,path='tasks',component='work-tasks/index',menu_name='作业任务',visible='0',status='0',update_by='admin',update_time=NOW()
WHERE path='work-tasks' AND menu_type='C' LIMIT 1;
UPDATE sys_menu SET parent_id=@work_id,order_num=2,path='fences',component='geo-fences/index',menu_name='电子围栏',visible='0',status='0',update_by='admin',update_time=NOW()
WHERE path='geo-fences' AND menu_type='C' LIMIT 1;
UPDATE sys_menu SET parent_id=@audit_id,order_num=1,path='events',component='audit/events/index',menu_name='事件记录',visible='0',status='0',perms='wear:event:list',update_by='admin',update_time=NOW()
WHERE path='events' AND menu_type='C' LIMIT 1;

INSERT INTO sys_menu (menu_name,parent_id,order_num,path,component,query,is_frame,is_cache,menu_type,visible,status,perms,icon,create_by,create_time,remark)
SELECT '组织资料',@master_id,2,'organization','organization/index','',1,0,'C','0','0','wear:person:list','peoples','admin',NOW(),'班组与承包商维护'
WHERE @master_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id=@master_id AND path='organization');
INSERT INTO sys_menu (menu_name,parent_id,order_num,path,component,query,is_frame,is_cache,menu_type,visible,status,perms,icon,create_by,create_time,remark)
SELECT '产品型号',@assets_id,2,'models','product-models/index','',1,0,'C','0','0','wear:model:list','component','admin',NOW(),'产品型号与能力维护'
WHERE @assets_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id=@assets_id AND path='models');
INSERT INTO sys_menu (menu_name,parent_id,order_num,path,component,query,is_frame,is_cache,menu_type,visible,status,perms,icon,create_by,create_time,remark)
SELECT '领用归还记录',@assets_id,3,'assignments','assignments/index','',1,0,'C','0','0','wear:assignment:list','time-range','admin',NOW(),'设备领用归还审计'
WHERE @assets_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id=@assets_id AND path='assignments');
INSERT INTO sys_menu (menu_name,parent_id,order_num,path,component,query,is_frame,is_cache,menu_type,visible,status,perms,icon,create_by,create_time,remark)
SELECT '文件记录',@audit_id,2,'files','audit/files/index','',1,0,'C','0','0','wear:file:list','file','admin',NOW(),'设备文件只读审计'
WHERE @audit_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys_menu WHERE parent_id=@audit_id AND path='files');

-- 正式 PC 不注册现场操作、旧帽页、未交付页和旧大屏。
UPDATE sys_menu SET visible='1',status='1',update_by='admin',update_time=NOW()
WHERE path IN ('duty','locations','group','hat','live','track','fence','sos','file','intercom','tts','legacy')
   OR (parent_id=0 AND path IN ('business','secure'));
UPDATE sys_menu SET visible='1',status='1',update_by='admin',update_time=NOW()
WHERE component IN ('secure/helmet/index','secure/limited/index','system/hat/index','system/module/index');

-- 新目录先继承其可见子菜单的角色，避免扩大原有数据权限。
INSERT IGNORE INTO sys_role_menu(role_id,menu_id)
SELECT DISTINCT rm.role_id,m.parent_id FROM sys_role_menu rm JOIN sys_menu m ON m.menu_id=rm.menu_id
WHERE m.parent_id IN (@master_id,@assets_id,@work_id,@audit_id);

-- 管理概览对平台角色开放；审计目录及其页面对审查/只读/值班角色开放。
SET @dashboard_id := (SELECT menu_id FROM sys_menu WHERE parent_id=0 AND path='dashboard' LIMIT 1);
INSERT IGNORE INTO sys_role_menu(role_id,menu_id)
SELECT role_id,@dashboard_id FROM sys_role WHERE role_key IN ('admin','wear_platform_admin','wear_device_admin','wear_duty','wear_reviewer','wear_team_lead','wear_readonly');
INSERT IGNORE INTO sys_role_menu(role_id,menu_id)
SELECT r.role_id,m.menu_id FROM sys_role r JOIN sys_menu m ON m.menu_id IN (@audit_id)
WHERE r.role_key IN ('admin','wear_platform_admin','wear_device_admin','wear_duty','wear_reviewer','wear_team_lead','wear_readonly');
INSERT IGNORE INTO sys_role_menu(role_id,menu_id)
SELECT r.role_id,m.menu_id FROM sys_role r JOIN sys_menu m ON m.parent_id=@audit_id
WHERE r.role_key IN ('admin','wear_platform_admin','wear_device_admin','wear_duty','wear_reviewer','wear_team_lead','wear_readonly');

-- 移除所有角色对旧版入口的菜单授权；回退只通过登录后的构建开关直达。
DELETE rm FROM sys_role_menu rm JOIN sys_menu m ON m.menu_id=rm.menu_id
WHERE m.path IN ('duty','locations','group','hat','live','track','fence','sos','file','intercom','tts','legacy')
   OR m.component IN ('secure/helmet/index','secure/limited/index','system/hat/index','system/module/index');

-- 按正式后台职责重建角色菜单：平台管理员全量；设备管理员仅设备域；审查/只读/现场角色仅审计。
DELETE rm FROM sys_role_menu rm
JOIN sys_role r ON r.role_id=rm.role_id
JOIN sys_menu m ON m.menu_id=rm.menu_id
WHERE r.role_key IN ('wear_reviewer','wear_readonly','wear_duty','wear_team_lead')
  AND (m.menu_id IN (@master_id,@assets_id,@work_id) OR m.parent_id IN (@master_id,@assets_id,@work_id));
DELETE rm FROM sys_role_menu rm
JOIN sys_role r ON r.role_id=rm.role_id
JOIN sys_menu m ON m.menu_id=rm.menu_id
WHERE r.role_key='wear_device_admin'
  AND (m.menu_id IN (@master_id,@work_id) OR m.parent_id IN (@master_id,@work_id));

INSERT IGNORE INTO sys_role_menu(role_id,menu_id)
SELECT r.role_id,m.menu_id FROM sys_role r JOIN sys_menu m
  ON m.menu_id IN (@dashboard_id,@master_id,@assets_id,@work_id,@audit_id)
  OR m.parent_id IN (@master_id,@assets_id,@work_id,@audit_id)
WHERE r.role_key IN ('admin','wear_platform_admin');
INSERT IGNORE INTO sys_role_menu(role_id,menu_id)
SELECT r.role_id,m.menu_id FROM sys_role r JOIN sys_menu m
  ON m.menu_id=@assets_id OR m.parent_id=@assets_id
WHERE r.role_key='wear_device_admin';

SET @people_id := (SELECT menu_id FROM sys_menu WHERE parent_id=@master_id AND path='people' LIMIT 1);
SET @organization_id := (SELECT menu_id FROM sys_menu WHERE parent_id=@master_id AND path='organization' LIMIT 1);
SET @spaces_id := (SELECT menu_id FROM sys_menu WHERE parent_id=@master_id AND path='spaces' LIMIT 1);
SET @devices_id := (SELECT menu_id FROM sys_menu WHERE parent_id=@assets_id AND path='devices' LIMIT 1);
SET @models_id := (SELECT menu_id FROM sys_menu WHERE parent_id=@assets_id AND path='models' LIMIT 1);
SET @assignments_id := (SELECT menu_id FROM sys_menu WHERE parent_id=@assets_id AND path='assignments' LIMIT 1);
SET @tasks_id := (SELECT menu_id FROM sys_menu WHERE parent_id=@work_id AND path='tasks' LIMIT 1);
SET @fences_id := (SELECT menu_id FROM sys_menu WHERE parent_id=@work_id AND path='fences' LIMIT 1);
SET @events_id := (SELECT menu_id FROM sys_menu WHERE parent_id=@audit_id AND path='events' LIMIT 1);
SET @files_id := (SELECT menu_id FROM sys_menu WHERE parent_id=@audit_id AND path='files' LIMIT 1);

-- 功能权限不产生新页面，只用于按钮和接口鉴权；重复执行按 perms 去重。
INSERT INTO sys_menu(menu_name,parent_id,order_num,path,component,query,is_frame,is_cache,menu_type,visible,status,perms,icon,create_by,create_time,remark)
SELECT x.menu_name,x.parent_id,x.order_num,'#','', '',1,0,'F','0','0',x.perms,'#','admin',NOW(),'V011 后台功能权限'
FROM (
  SELECT '人员维护' menu_name,@people_id parent_id,1 order_num,'wear:person:edit' perms UNION ALL
  SELECT '人员导入',@people_id,2,'wear:person:import' UNION ALL
  SELECT '人员导出',@people_id,3,'wear:person:export' UNION ALL
  SELECT '组织维护',@organization_id,1,'wear:team:edit' UNION ALL
  SELECT '承包商维护',@organization_id,2,'wear:contractor:edit' UNION ALL
  SELECT '区域维护',@spaces_id,1,'wear:space:edit' UNION ALL
  SELECT '设备维护',@devices_id,1,'wear:device:edit' UNION ALL
  SELECT '设备导入',@devices_id,2,'wear:device:import' UNION ALL
  SELECT '设备导出',@devices_id,3,'wear:device:export' UNION ALL
  SELECT '型号维护',@models_id,1,'wear:model:edit' UNION ALL
  SELECT '型号导入',@models_id,2,'wear:model:import' UNION ALL
  SELECT '型号导出',@models_id,3,'wear:model:export' UNION ALL
  SELECT '资产领用归还',@assignments_id,1,'wear:assignment:issue' UNION ALL
  SELECT '资产记录导出',@assignments_id,2,'wear:assignment:export' UNION ALL
  SELECT '任务维护',@tasks_id,1,'wear:task:edit' UNION ALL
  SELECT '任务导出',@tasks_id,2,'wear:task:export' UNION ALL
  SELECT '围栏维护',@fences_id,1,'wear:fence:edit' UNION ALL
  SELECT '围栏导出',@fences_id,2,'wear:fence:export' UNION ALL
  SELECT '事件详情',@events_id,1,'wear:event:query' UNION ALL
  SELECT '事件导出',@events_id,2,'wear:event:export' UNION ALL
  SELECT '文件详情',@files_id,1,'wear:file:query' UNION ALL
  SELECT '文件导出',@files_id,2,'wear:file:export'
) x
WHERE x.parent_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys_menu e WHERE e.perms=x.perms);

INSERT IGNORE INTO sys_role_menu(role_id,menu_id)
SELECT r.role_id,m.menu_id FROM sys_role r JOIN sys_menu m
  ON m.parent_id IN (@people_id,@organization_id,@spaces_id,@devices_id,@models_id,@assignments_id,@tasks_id,@fences_id,@events_id,@files_id)
WHERE r.role_key IN ('admin','wear_platform_admin');
INSERT IGNORE INTO sys_role_menu(role_id,menu_id)
SELECT r.role_id,m.menu_id FROM sys_role r JOIN sys_menu m
  ON m.parent_id IN (@devices_id,@models_id,@assignments_id)
WHERE r.role_key='wear_device_admin';
INSERT IGNORE INTO sys_role_menu(role_id,menu_id)
SELECT r.role_id,m.menu_id FROM sys_role r JOIN sys_menu m
  ON m.parent_id IN (@events_id,@files_id)
WHERE r.role_key IN ('wear_reviewer','wear_readonly','wear_duty','wear_team_lead','wear_device_admin');
