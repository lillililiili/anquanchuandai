"""Local fixture batch tools. No database writes occur on import."""
import subprocess, json, gzip, hashlib, re
from pathlib import Path
from datetime import datetime

ROOT = Path(__file__).resolve().parent
DB = 'melhat_local'

def mysql(sql, db=DB):
    assert re.fullmatch(r'melhat_(local|verify_\d+)', db), db
    p = subprocess.run(['docker','exec','-i','melhat-mysql','sh','-c',
        'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot --default-character-set=utf8mb4 --batch --raw --skip-column-names -D '+db],
        input=sql, text=True, encoding='utf-8', capture_output=True)
    if p.returncode:
        raise RuntimeError(p.stderr[-4000:])
    return p.stdout

def rows(sql, db=DB):
    return [json.loads(s) for s in mysql(sql,db).splitlines() if s.strip()]

def tables(db=DB):
    return rows("SELECT JSON_QUOTE(table_name) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE' ORDER BY table_name;",db)

def counts(db=DB):
    found=rows('\n'.join("SELECT JSON_OBJECT('table','"+t+"','count',COUNT(*)) FROM `"+t+"`;" for t in tables(db)),db)
    return {r['table']:r['count'] for r in found}

def save(path,obj):
    path.write_text(json.dumps(obj,ensure_ascii=False,indent=2),encoding='utf-8')

def backup():
    stamp=datetime.now().strftime('%Y%m%d%H%M%S')
    batch=ROOT/('执行批次-'+stamp)
    batch.mkdir()
    before=counts()
    save(batch/'导入前表计数.json',before)
    dump=batch/'数据库-导入前.sql.gz'
    p=subprocess.run(['docker','exec','melhat-mysql','sh','-c',
        'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysqldump -uroot --single-transaction --routines --triggers --events --hex-blob --set-gtid-purged=OFF --no-tablespaces --default-character-set=utf8mb4 "$MYSQL_DATABASE"'],capture_output=True,check=True)
    with gzip.open(dump,'wb') as f: f.write(p.stdout)
    media=batch/'上传目录-导入前.tar.gz'
    with media.open('wb') as f:
        subprocess.run(['docker','exec','melhat-backend','tar','-czf','-','-C','/data','.'],stdout=f,stderr=subprocess.PIPE,check=True)
    scratch='melhat_verify_'+stamp
    mysql('CREATE DATABASE `'+scratch+'` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;')
    mysql(p.stdout.decode('utf-8'),scratch)
    restored=counts(scratch)
    assert before==restored, 'Restored counts differ'
    meta={'batch':batch.name,'createdAt':datetime.now().astimezone().isoformat(),'database':DB,'scratchDatabase':scratch,'restoreVerified':True,'tableCount':len(before),'files':{f.name:{'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in [dump,media]}}
    save(batch/'备份验证.json',meta)
    print(json.dumps(meta,ensure_ascii=False))

if __name__=='__main__': backup()
