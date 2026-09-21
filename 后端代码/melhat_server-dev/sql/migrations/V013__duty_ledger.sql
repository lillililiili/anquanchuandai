-- Additive and repeatable. Historical intervals are explicitly marked inferred.
CREATE TABLE IF NOT EXISTS wear_duty_shift (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  site_id BIGINT NOT NULL,
  user_id BIGINT NOT NULL,
  started_at DATETIME NOT NULL,
  ended_at DATETIME NULL,
  source_handover_id BIGINT NULL,
  change_type VARCHAR(32) NOT NULL,
  actor_user_id BIGINT NULL,
  reason VARCHAR(500) NULL,
  UNIQUE KEY uk_duty_source (source_handover_id),
  KEY idx_duty_site_time (site_id, started_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS wear_duty_station (
  site_id BIGINT NOT NULL PRIMARY KEY,
  current_shift_id BIGINT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS wear_duty_handover_audit (
  handover_id BIGINT NOT NULL PRIMARY KEY,
  action VARCHAR(32) NOT NULL,
  actor_user_id BIGINT NOT NULL,
  acted_at DATETIME NOT NULL,
  reason VARCHAR(500) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Only confirmation timestamps are known. Do not invent a start for senders.
INSERT IGNORE INTO wear_duty_shift
 (site_id,user_id,started_at,ended_at,source_handover_id,change_type,actor_user_id,reason)
SELECT h.site_id,h.to_user_id,h.confirmed_at,
 (SELECT MIN(n.confirmed_at) FROM wear_duty_handover n WHERE n.site_id=h.site_id
  AND n.status='confirmed' AND (n.confirmed_at>h.confirmed_at OR (n.confirmed_at=h.confirmed_at AND n.id>h.id))),
 h.id,'legacy_confirmation',h.to_user_id,'历史确认记录推算；未记录的值班起点不补算'
FROM wear_duty_handover h WHERE h.status='confirmed' AND h.confirmed_at IS NOT NULL;

INSERT IGNORE INTO wear_duty_station(site_id,current_shift_id)
SELECT s.id,(SELECT d.id FROM wear_duty_shift d WHERE d.site_id=s.id ORDER BY d.started_at DESC,d.id DESC LIMIT 1)
FROM wear_site s;
