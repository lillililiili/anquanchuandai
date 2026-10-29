"""Reproducible public V2 contract and synthetic fixtures; contains no production credentials."""
from pathlib import Path
import base64, hashlib, hmac, json

ROOT = Path(__file__).resolve().parent
EXAMPLES = ROOT / 'examples'
EXAMPLES.mkdir(exist_ok=True)
UTC_PATTERN = r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$'
def string(**kw): return {'type':'string', **kw}
def nullable(kind='string', **kw): return {'type':[kind,'null'], **kw}
def enum(*values): return string(enum=list(values))
def ref(name): return {'$ref':f'#/components/schemas/{name}'}
def obj(props, required=None, **kw): return {'type':'object','properties':props,'required':list(props) if required is None else required,'additionalProperties':False,**kw}
def timestamp(can_null=False): return (nullable if can_null else string)(format='date-time',pattern=UTC_PATTERN)
def array(items, **kw): return {'type':'array','items':items,**kw}
def write(path, value): path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

validity=enum('VALID','STALE','UNKNOWN','UNSUPPORTED')
common={'sourcePlatform':string(minLength=1,maxLength=128),'deviceType':enum('HELMET','SAFETY_BELT'),'deviceId':string(pattern=r'^[A-Za-z0-9._-]{1,64}$'),'deviceModel':nullable(description='Actual registered model; null when not recorded. Never inferred from device type.')}
position=obj({'longitude':{'type':'number','minimum':-180,'maximum':180},'latitude':{'type':'number','minimum':-90,'maximum':90},'coordinateSystem':enum('WGS84','GCJ02'),
    'altitude':nullable('number',description='Mean-sea-level altitude, metres. Current adapter returns null: datum unverified.'),
    'relativeHeight':nullable('number',description='Metres; current adapter returns null because reference is unverified.'),'heightReference':enum('POWER_ON','CALIBRATED','UNKNOWN'),
    'speed':nullable('number',minimum=0,description='km/h. Current adapter returns null: raw units unverified.'),'direction':nullable('number',minimum=0,exclusiveMaximum=360,description='North=0, clockwise ground course; current adapter returns null.'),
    'positionTime':timestamp(),'timeSource':enum('DEVICE','PLATFORM'),'positionMethod':enum('GNSS','WIFI','CELL','OTHER','UNKNOWN'),'historical':{'type':'boolean'}},
    description='Known coordinate reference, valid source quality and original observation time required. Current adapter uses platform receipt time (PLATFORM). Unknown/unfixed coordinates are position=null. Belt reference is currently unknown; a per-device location profile may be enabled only after evidence-based commissioning. Such a profile affects current positions only and never reinterprets historical alarm snapshots.')
position['allOf']=[{'not':{'properties':{'longitude':{'const':0},'latitude':{'const':0}},'required':['longitude','latitude']}}]
observed={'observedAt':timestamp(True),'validity':validity}
battery=obj({'percent':nullable('number',minimum=0,maximum=100,description='Remaining charge, %; unknown is null, not zero.'),'voltageMv':nullable('integer',minimum=0),**observed})
network=obj({'type':enum('CELLULAR_4G','WIFI','OTHER','UNKNOWN'),'signalLevel':nullable('integer',minimum=0,maximum=5,description='Dimensionless level. Current adapter returns null/UNKNOWN until mapping is verified.'),**observed})
wear=obj({'status':enum('UNKNOWN','NOT_WORN','WORN','UNSUPPORTED'),**observed},description='Body wearing status. Current safety-belt adapter returns UNKNOWN; hook attachment does not establish body wearing.')
hook=obj({'status':enum('UNKNOWN','ATTACHED','DETACHED','UNSUPPORTED'),**observed},description='Attachment detection, not proof of mechanical locking/load safety. Helmet hooks are UNSUPPORTED; belt mapping must be explicitly confirmed.')
status_props={'onlineStatus':enum('ONLINE','OFFLINE'),'lastSeenAt':timestamp(True),'offlineTimeoutSeconds':{'type':'integer','minimum':1,'description':'Actual configured device heartbeat timeout.'},'telemetryMaxAgeSeconds':{'type':'integer','minimum':1,'description':'Actual freshness threshold; currently equals the device heartbeat timeout.'},'battery':ref('Battery'),'network':ref('Network'),'wear':ref('Wear'),'hookA':ref('Hook'),'hookB':ref('Hook')}
alarm_types=['SOS','HELMET_REMOVED','AREA_EXIT','RESTRICTED_AREA_ENTRY','TEMPERATURE_HIGH','FALL_OR_IMPACT','FALL','IMPACT','IMMOBILITY','LOW_BATTERY','ELECTRIC_PROXIMITY','HEIGHT_EXCEEDED','BOTH_HOOKS_DETACHED','SINGLE_HOOK_DETACHED','LOW_ANCHOR','BEACON_ENTER','BEACON_EXIT','BODY_TEMPERATURE_HIGH','HEART_RATE_ABNORMAL','BLOOD_PRESSURE_ABNORMAL','UNKNOWN']
alarm_props={'eventId':string(minLength=1,maxLength=128,description='Opaque stable business-event ID, not necessarily UUID. Deduplicate by (sourcePlatform,eventId).'),
    'occurredAt':timestamp(True),'receivedAt':timestamp(True),'alarmType':enum(*alarm_types),'alarmContent':string(minLength=1,maxLength=1000),
    'rawAlarmType':nullable(maxLength=64),'rawAlarmName':nullable(maxLength=200),'alarmOrigin':enum('DEVICE','PLATFORM'),
    'positionSource':enum('EVENT','LAST_KNOWN','NONE'),'position':{'anyOf':[ref('Position'),{'type':'null'}]},'positionAgeSeconds':nullable('number',minimum=0,maximum=300)}
error_codes=[40001,40002,40101,40102,40301,40401,40902,40903,41001,41301,41501,42901,50201,50300,50301,50302,50303,50304]
envelope={'code':{'type':'integer','const':0},'message':{'const':'success','type':'string'},'requestId':string(format='uuid'),'serverTime':timestamp()}
schemas={
    'DeviceReference':obj({'deviceType':common['deviceType'],'deviceId':common['deviceId']}),
    'DeviceQuery':obj({'devices':array(ref('DeviceReference'),minItems=1,maxItems=100,uniqueItems=True)},description='At least one explicit device. Any unauthorized reference rejects the entire batch; duplicates are rejected.'),
    'AlarmQuery':obj({'cursor':nullable(maxLength=512,description='Required; null begins at the earliest retained authorized alarm. Subsequent requests use nextCursor unchanged.'),'limit':{'type':'integer','minimum':1,'maximum':500,'default':100}},required=['cursor']),
    'Position':position,'Battery':battery,'Network':network,'Wear':wear,'Hook':hook,
    'PositionItem':obj({**common,'position':{'anyOf':[ref('Position'),{'type':'null'}]},'validity':enum('VALID','STALE','UNKNOWN')}),
    'StatusItem':obj({**common,**status_props}),
    'AlarmItem':obj({**common,**alarm_props},description='Immutable first occurrence only; business processing, claim or verification is not an alarm clear. Current implementation exports confirmed SOS and UNKNOWN with original vendor code; other enum values are reserved until verified. Historical times can be null when unrecoverable.'),
    'PositionResponse':obj({**envelope,'data':obj({'items':array(ref('PositionItem'))})}),
    'StatusResponse':obj({**envelope,'data':obj({'items':array(ref('StatusItem'))})}),
    'AlarmResponse':obj({**envelope,'data':obj({'items':array(ref('AlarmItem')),'nextCursor':string(minLength=1,maxLength=512),'hasMore':{'type':'boolean'}})}),
    'ErrorResponse':obj({'code':{'type':'integer','enum':error_codes},'message':string(),'requestId':string(format='uuid'),'serverTime':timestamp(),'data':{'type':'null'}})
}
schemas['PositionItem']['allOf']=[{'if':{'properties':{'position':{'type':'null'}}},'then':{'properties':{'validity':{'const':'UNKNOWN'}}}}]
schemas['StatusItem']['allOf']=[{'if':{'properties':{'onlineStatus':{'const':'OFFLINE'}}},'then':{'properties':{key:{'properties':{'validity':{'not':{'const':'VALID'}}}} for key in ['battery','network','wear','hookA','hookB']}}}]
schemas['AlarmItem']['allOf']=[{'if':{'properties':{'positionSource':{'const':'NONE'}}},'then':{'properties':{'position':{'type':'null'},'positionAgeSeconds':{'type':'null'}}},'else':{'properties':{'position':ref('Position'),'positionAgeSeconds':{'type':'number','minimum':0,'maximum':300}}}}]
header_defs=[('X-App-Id',string(pattern=r'^[A-Za-z0-9_-]{1,64}$'),'Dedicated partner application ID; human login sessions are rejected.'),
    ('X-Timestamp',string(pattern=r'^[0-9]{1,12}$'),'Unix seconds; server permits clock skew up to 300 seconds.'),
    ('X-Nonce',string(pattern=r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'),'New UUID per HTTP attempt; replay identity is case-insensitive within this application; stored atomically for at least 600 seconds (implementation 601 seconds covers inclusive clock-window boundaries).'),
    ('X-Signature',string(pattern=r'^[0-9a-f]{64}$'),'Lowercase HMAC-SHA256 of six newline-separated fields: POST, exact full path, appId, timestamp, nonce, lowercase SHA256(raw UTF-8 body). No trailing newline. Secret is Base64-decoded into exactly 32 bytes, not used as UTF-8 text.')]
error_messages={'400':'40001 invalid request; 40002 invalid/tampered cursor or changed scope.','401':'40101 invalid credentials or human session provided; 40102 timestamp outside window.',
    '403':'40301 device scope denied; whole batch rejected.','404':'40401 gateway method or route not allowed.','409':'40902 nonce already used: retry with new timestamp/nonce/signature; 40903 cursor ahead of durable journal: restore/recovery required.',
    '410':'41001 retained cursor has expired; coordinate historical recovery, never silently reset to newest.',
    '413':'41301 body exceeds 64 KiB.','415':'41501 unsupported content type or content encoding.','429':'42901 gateway rate limit; retry with backoff.',
    '502':'50201 gateway cannot reach upstream.','503':'50300 temporary service failure; 50301 replay store unavailable; 50302 API disabled; 50303 application configuration invalid; 50304 device registry unavailable/ambiguous.'}
paths={}
for kind,request_schema,response_schema in [('positions','DeviceQuery','PositionResponse'),('statuses','DeviceQuery','StatusResponse'),('alarms','AlarmQuery','AlarmResponse')]:
    responses={'200':{'description':'Query succeeded. Persist a complete alarm page locally before advancing nextCursor.','content':{'application/json':{'schema':ref(response_schema)}}}}
    responses.update({status:{'description':message,'content':{'application/json':{'schema':ref('ErrorResponse')}}} for status,message in error_messages.items()})
    paths[f'/openapi/wearables/v2/{kind}/query']={'post':{'operationId':f'query{kind.title()}','summary':f'Query {kind}',
        'description':'Fuda initiates this read-only query against our platform. No query string, compression, trailing slash, Authorization or X-Wearable-Token. Body <=65536 bytes. Alarm responses use a persistent committed-order cursor, not event time or page number.' if kind=='alarms' else 'Fuda initiates this read-only query against our platform. No query string, compression, trailing slash, Authorization or X-Wearable-Token. Body <=65536 bytes. Response preserves request device order.',
        'security':[{'ApplicationId':[]}],'parameters':[{'name':name,'in':'header','required':True,'schema':schema,'description':description} for name,schema,description in header_defs],
        'requestBody':{'required':True,'content':{'application/json':{'schema':ref(request_schema)}}},'responses':responses}}
api={'openapi':'3.1.0','info':{'title':'智能穿戴平台—福大 V2 主动拉取接口','version':'2.0.0',
    'description':'Implementation contract for the isolated backend. Default disabled; deployment and joint acceptance are still required. Three HTTP query endpoints; GB/T 28181-2022 video uses a separate cascade contract. Source platform identifier must remain stable. Credentials and authorized devices are private configuration. Alarm cursor is bound to app/key and current authorized real-device set; losing/changing scope/key requires controlled resynchronization. No automatic journal deletion in this release. Repeated cursor reads are safe; receiver deduplicates stable event IDs. Position/status provide latest snapshots, not complete intermediate history.'},
    'servers':[{'url':'https://wearable-api.example.invalid','description':'Placeholder; replace only with the accepted test/production base URL.'}],
    'paths':paths,'components':{'securitySchemes':{'ApplicationId':{'type':'apiKey','in':'header','name':'X-App-Id','description':'App ID alone is insufficient. All four HMAC headers are mandatory.'}},'schemas':schemas}}
write(ROOT/'openapi.json',api)

base={'sourcePlatform':'wearable-example','deviceType':'HELMET','deviceId':'DEMO-HELMET-01','deviceModel':None}
def response(data): return {'code':0,'message':'success','requestId':'00000000-0000-4000-8000-000000000002','serverTime':'2026-10-27T08:00:00.000Z','data':data}
pos={'longitude':119.2,'latitude':26.1,'coordinateSystem':'GCJ02','altitude':None,'relativeHeight':None,'heightReference':'UNKNOWN','speed':None,'direction':None,'positionTime':'2026-10-27T07:59:50.000Z','timeSource':'PLATFORM','positionMethod':'GNSS','historical':False}
state={**base,'onlineStatus':'ONLINE','lastSeenAt':'2026-10-27T07:59:50.000Z','offlineTimeoutSeconds':45,'telemetryMaxAgeSeconds':45,
    'battery':{'percent':78,'voltageMv':None,'observedAt':'2026-10-27T07:59:50.000Z','validity':'VALID'},
    'network':{'type':'UNKNOWN','signalLevel':None,'observedAt':None,'validity':'UNKNOWN'},
    'wear':{'status':'WORN','observedAt':'2026-10-27T07:59:50.000Z','validity':'VALID'},
    'hookA':{'status':'UNSUPPORTED','observedAt':None,'validity':'UNSUPPORTED'},'hookB':{'status':'UNSUPPORTED','observedAt':None,'validity':'UNSUPPORTED'}}
alarm={**base,'eventId':'example-stable-event-001','occurredAt':'2026-10-27T07:59:55.000Z','receivedAt':'2026-10-27T07:59:55.000Z','alarmType':'SOS','alarmContent':'设备发起 SOS','rawAlarmType':None,'rawAlarmName':None,'alarmOrigin':'DEVICE','positionSource':'LAST_KNOWN','position':pos,'positionAgeSeconds':5}
test_key=bytes(range(32));app='fuda-public-test';scope=['HELMET:DEMO-HELMET-01'];scope_hash=hashlib.sha256((app+'\n'+'\n'.join(scope)).encode()).hexdigest()
payload=base64.urlsafe_b64encode(('2|1|'+scope_hash).encode()).decode().rstrip('=');cursor=payload+'.'+hmac.new(test_key,('FUDA-CURSOR\n'+payload).encode(),hashlib.sha256).hexdigest()
fixtures={'positions-request':{'devices':[{'deviceType':'HELMET','deviceId':'DEMO-HELMET-01'}]},'statuses-request':{'devices':[{'deviceType':'HELMET','deviceId':'DEMO-HELMET-01'}]},'alarms-request':{'cursor':None,'limit':100},
    'positions-success':response({'items':[{**base,'position':pos,'validity':'VALID'}]}),'positions-unknown':response({'items':[{**base,'position':None,'validity':'UNKNOWN'}]}),
    'statuses-success':response({'items':[state]}),'alarms-success':response({'items':[alarm],'nextCursor':cursor,'hasMore':False}),'alarms-empty':response({'items':[],'nextCursor':cursor,'hasMore':False}),
    'error-response':{'code':40301,'message':'Device outside authorized scope','requestId':'00000000-0000-4000-8000-000000000003','serverTime':'2026-10-27T08:00:00.000Z','data':None}}
belt_state={**state,'deviceType':'SAFETY_BELT','deviceId':'DEMO-BELT-01',
    'wear':{'status':'UNKNOWN','observedAt':'2026-10-27T07:59:50.000Z','validity':'UNKNOWN'},
    'hookA':{'status':'ATTACHED','observedAt':'2026-10-27T07:59:50.000Z','validity':'VALID'},'hookB':{'status':'DETACHED','observedAt':'2026-10-27T07:59:50.000Z','validity':'VALID'}}
fixtures['statuses-belt-success']=response({'items':[belt_state]})
fixtures['alarms-unknown']=response({'items':[{**alarm,'deviceType':'SAFETY_BELT','deviceId':'DEMO-BELT-01','eventId':'example-stable-event-002','alarmType':'UNKNOWN','alarmContent':'设备报警（原始码：6）','rawAlarmType':'6','positionSource':'NONE','position':None,'positionAgeSeconds':None}],'nextCursor':cursor,'hasMore':False})
for name,value in fixtures.items(): write(EXAMPLES/(name+'.json'),value)
body=json.dumps(fixtures['positions-request'],ensure_ascii=False,separators=(',',':'));path='/openapi/wearables/v2/positions/query';timestamp_value='1793088000';nonce='00000000-0000-4000-8000-000000000001'
digest=hashlib.sha256(body.encode()).hexdigest();canonical='\n'.join(['POST',path,app,timestamp_value,nonce,digest]);signature=hmac.new(test_key,canonical.encode(),hashlib.sha256).hexdigest()
write(EXAMPLES/'signature-vector.json',{'warning':'PUBLIC SYNTHETIC TEST KEY ONLY. Never enable this key or these device IDs in deployment. Fixed timestamp is not a live request.',
    'secretBase64':base64.b64encode(test_key).decode(),'decodedKeyHex':test_key.hex(),'method':'POST','path':path,'bodyUtf8':body,'bodySha256':digest,'canonicalUtf8':canonical,
    'headers':{'X-App-Id':app,'X-Timestamp':timestamp_value,'X-Nonce':nonce,'X-Signature':signature},'expectedSignature':signature})
write(EXAMPLES/'cursor-vector.json',{'warning':'PUBLIC SYNTHETIC TEST ONLY','appId':app,'authorizedKeys':scope,'after':1,'secretBase64':base64.b64encode(test_key).decode(),'cursor':cursor})

if __name__=='__main__':
    try:
        from jsonschema import Draft202012Validator, RefResolver
        mapping={'positions-request':'DeviceQuery','statuses-request':'DeviceQuery','alarms-request':'AlarmQuery','positions-success':'PositionResponse','positions-unknown':'PositionResponse','statuses-success':'StatusResponse','statuses-belt-success':'StatusResponse','alarms-success':'AlarmResponse','alarms-unknown':'AlarmResponse','alarms-empty':'AlarmResponse','error-response':'ErrorResponse'}
        for name,schema_name in mapping.items(): Draft202012Validator(ref(schema_name),resolver=RefResolver.from_schema(api)).validate(fixtures[name])
        print('Generated OpenAPI and 13 synthetic examples; 11 request/response fixtures validated.')
    except ImportError:
        print('Generated OpenAPI and examples; jsonschema is unavailable for fixture validation.')
