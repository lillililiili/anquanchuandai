"""Read-only local MySQL inventory. Never inserts or changes business data."""
import json, subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent

def read(sql):
    if any(word in sql.upper() for word in ['INSERT ', 'UPDATE ', 'DELETE ', 'DROP ', 'ALTER ', 'TRUNCATE ', 'REPLACE ']):
        raise ValueError('Only read-only inspection is allowed')
    command = ['docker', 'exec', '-i', 'melhat-mysql', 'sh', '-c',
               'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot --default-character-set=utf8mb4 --batch --raw --skip-column-names -D "$MYSQL_DATABASE"']
    result = subprocess.run(command, input='SET SESSION TRANSACTION READ ONLY; START TRANSACTION READ ONLY;\n'+sql+'\nCOMMIT;', text=True, encoding='utf-8', capture_output=True, check=True)
    return [json.loads(line) for line in result.stdout.splitlines() if line.strip()]

if __name__ == '__main__':
    schema = read("SELECT JSON_OBJECT('table',table_name,'column',column_name,'type',column_type,'nullable',is_nullable,'key',column_key,'default',column_default,'comment',column_comment) FROM information_schema.columns WHERE table_schema=DATABASE() AND (table_name LIKE 'wear_%' OR table_name IN ('sys_user','sys_role','sys_user_role','sys_dept','safety_hat_info','safety_hat_location_record','file_record','real_time_alarm','sos_alarm_record','electronic_fence','demo_compat_record')) ORDER BY table_name,ordinal_position;")
    tables = sorted({row['table'] for row in schema})
    counts = read('\n'.join("SELECT JSON_OBJECT('table','%s','count',COUNT(*)) FROM `%s`;"%(t,t) for t in tables))
    selected = [t for t in tables if t.startswith('wear_')]
    records = {}
    for table in selected:
        cols = [x['column'] for x in schema if x['table']==table]
        fields = ','.join("'%s',`%s`"%(c,c) for c in cols)
        records[table] = read('SELECT JSON_OBJECT('+fields+') FROM `'+table+'` LIMIT 25;')
    records['sys_user'] = read("SELECT JSON_OBJECT('id',user_id,'username',user_name,'nickname',nick_name,'deptId',dept_id,'status',status,'deleted',del_flag) FROM sys_user;")
    records['sys_role'] = read("SELECT JSON_OBJECT('id',role_id,'name',role_name,'key',role_key,'status',status) FROM sys_role;")
    records['sys_user_role'] = read("SELECT JSON_OBJECT('userId',user_id,'roleId',role_id) FROM sys_user_role;")
    data = {'capturedAt':datetime.now().astimezone().isoformat(), 'mode':'READ ONLY; no writes', 'database':'melhat_local','counts':counts,'schema':schema,'records':records}
    (ROOT/'数据库只读盘点.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),'utf-8')
    print(json.dumps(counts,ensure_ascii=False,indent=2))
