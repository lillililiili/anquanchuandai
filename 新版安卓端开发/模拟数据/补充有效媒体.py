"""Create 30 real, labelled test media files and auditable database records."""
import json,sys,subprocess,hashlib,urllib.request
from datetime import datetime,timedelta
from PIL import Image,ImageDraw,ImageFont
from 执行工具 import ROOT,mysql,rows,save
B=sorted(ROOT.glob('执行批次-*'))[-1]
MAN=json.loads((B/'批次清单.json').read_text('utf-8'))
assert not (B/'媒体已导入.json').exists(),'Media already imported'
sys.path.insert(0,str(B/'工具依赖'))
import imageio_ffmpeg
ffmpeg=imageio_ffmpeg.get_ffmpeg_exe()
media=B/'有效媒体';media.mkdir(exist_ok=True)
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',28)
small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
selected=[MAN['helmets'][i] for i in [0,2,3,5,7,20,21,23,24,25]]
files=[]
for i,d in enumerate(selected):
    stem=f'{MAN["batch"]}_{d["sn"]}_{i+1:02}'
    jpg=media/(stem+'.jpg')
    canvas=Image.new('RGB',(640,360),(239,244,250));draw=ImageDraw.Draw(canvas)
    draw.rectangle((0,0,640,64),fill=(24,66,109));draw.text((25,14),'联调测试素材 · 非真实现场',font=font,fill='white')
    draw.text((25,92),f'设备 {d["sn"]}  /  厂站 {d["site"]}',font=font,fill=(25,40,65))
    draw.text((25,148),f'测试编号 {i+1:02} · 图片 / 音频 / 视频预览',font=small,fill=(25,40,65))
    draw.rectangle((25,205,605,270),fill=(224,177,58));draw.text((42,224),'仅用于文件筛选、下载及播放器联调',font=small,fill=(25,40,65))
    draw.text((25,307),MAN['batch'],font=small,fill=(65,80,100));canvas.save(jpg,quality=90)
    mp3=media/(stem+'.mp3');mp4=media/(stem+'.mp4')
    subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-f','lavfi','-i',f'sine=frequency={440+i*30}:duration=3','-filter:a','volume=0.15','-codec:a','libmp3lame',str(mp3)],check=True,capture_output=True)
    subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-loop','1','-i',str(jpg),'-i',str(mp3),'-t','3','-r','15','-c:v','libx264','-pix_fmt','yuv420p','-c:a','aac','-movflags','+faststart',str(mp4)],check=True,capture_output=True)
    for f,typ in [(jpg,'image'),(mp3,'audio'),(mp4,'video')]:
        files.append({'fileName':f.name,'type':typ,'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'device':d})
dest='/data/upload/'+MAN['batch']
subprocess.run(['docker','exec','melhat-backend','mkdir','-p',dest],check=True,capture_output=True)
subprocess.run(['docker','cp',str(media)+ '/.','melhat-backend:'+dest+'/'],check=True,capture_output=True)
for f in files:
    u='http://127.0.0.1:18084/profile/'+MAN['batch']+'/'+f['fileName']
    content=urllib.request.urlopen(u,timeout=10).read()
    assert hashlib.sha256(content).hexdigest()==f['sha256'],f['fileName']

def val(s):return 'NULL' if s is None else (str(s) if isinstance(s,(int,float)) else "'"+str(s).replace("'","''")+"'")
def insert(t,**v):return 'INSERT INTO '+t+' ('+','.join(v)+') VALUES ('+','.join(val(x) for x in v.values())+');'
hatid=int(mysql('SELECT COALESCE(MAX(id),0)+1 FROM safety_hat_info;'))
mapid=int(mysql('SELECT COALESCE(MAX(id),0)+1 FROM wear_device_legacy_hat;'))
fileid=int(mysql('SELECT COALESCE(MAX(id),0)+1 FROM file_record;'))
sql=['START TRANSACTION;'];newids={'safety_hat_info':[],'wear_device_legacy_hat':[],'file_record':[]}
personrows=rows("SELECT JSON_OBJECT('id',id,'name',name,'account',account_user_id) FROM wear_person WHERE person_code LIKE 'QA-P%' OR person_code IN ('P-001','P-002','P-003','P-004','P-005') ORDER BY id;")
people={r['id']:r for r in personrows}
personids=MAN['ids']['wear_person']
now=datetime.now().replace(microsecond=0)
for i,d in enumerate(selected):
    p=people[personids[d['person']]];hid=hatid+i
    sql.append(insert('safety_hat_info',id=hid,site_id=d['site'],hat_number=d['sn'],bind_user_id=p['account'],bind_user_name=p['name'],bind_time=(now-timedelta(days=31)).strftime('%Y-%m-%d %H:%M:%S'),status='offline',create_by='demo',create_time=now.strftime('%Y-%m-%d %H:%M:%S')))
    sql.append(insert('wear_device_legacy_hat',id=mapid+i,device_id=d['id'],hat_id=hid,create_by='demo',create_time=now.strftime('%Y-%m-%d %H:%M:%S')))
    newids['safety_hat_info'].append(hid);newids['wear_device_legacy_hat'].append(mapid+i)
    for f in [f for f in files if f['device']['id']==d['id']]:
        t=(now-timedelta(days=i%7,hours=1)).strftime('%Y-%m-%d %H:%M:%S')
        sql.append(insert('file_record',id=fileid,file_name=f['fileName'],file_type=f['type'],file_url='http://127.0.0.1:18084/profile/'+MAN['batch']+'/'+f['fileName'],hat_id=hid,hat_number=d['sn'],user_name=p['name'],file_size=f['bytes'],upload_time=t,create_by='demo',create_time=t))
        f['id']=fileid;newids['file_record'].append(fileid);fileid+=1
sql.append('COMMIT;')
(B/'有效媒体导入.sql').write_text('\n'.join(sql),'utf-8')
mysql('\n'.join(sql))
save(B/'媒体已导入.json',{'at':now.isoformat(),'ids':newids,'containerDirectory':dest,'files':files})
print('Imported 30 playable/downloadable test files; all HTTP content hashes verified.')
