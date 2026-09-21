-- A discontinuous old handover chain cannot prove the previous holder's end time.
UPDATE wear_duty_shift d
JOIN (
  SELECT id,to_user_id,
    LEAD(from_user_id) OVER (PARTITION BY site_id ORDER BY confirmed_at,id) AS next_from,
    LEAD(id) OVER (PARTITION BY site_id ORDER BY confirmed_at,id) AS next_id
  FROM wear_duty_handover WHERE status='confirmed' AND confirmed_at IS NOT NULL
) h ON h.id=d.source_handover_id
SET d.ended_at=NULL,d.change_type='legacy_incomplete',d.reason='历史交接链不连续，结束时间未记录，无法计算完整时长'
WHERE d.change_type='legacy_confirmation' AND h.next_id IS NOT NULL AND h.next_from<>h.to_user_id;
