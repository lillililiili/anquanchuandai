-- 将系统中所有账号（管理员、值班员、复核员、现场人员对应用户等）密码统一重置为 admin123
-- RuoYi 默认 BCrypt 哈希值: $2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2
-- 对应明文密码: admin123

UPDATE sys_user 
   SET password = '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2'
 WHERE del_flag = '0';

-- 验证更新结果
SELECT user_id, user_name, nick_name, 'admin123' AS default_password, status 
  FROM sys_user 
 WHERE del_flag = '0';
