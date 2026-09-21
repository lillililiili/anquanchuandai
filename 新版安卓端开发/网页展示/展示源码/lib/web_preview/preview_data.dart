import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../wear/core.dart';

class PreviewCredentials implements CredentialStore {
  String? _token;
  @override Future<String?> read() async => _token;
  @override Future<void> write(String? token) async => _token = token;
}
WearSession createPreviewSession({required JsonMap snapshot}) => WearSession(
  credentials: PreviewCredentials(),
  dio: Dio(BaseOptions(baseUrl: 'https://preview.invalid'))
    ..transformer = SyncTransformer()
    ..httpClientAdapter = PreviewAdapter(snapshot),
);

/// A frozen business snapshot. All changes stay in memory; no network fallback.
class PreviewAdapter implements HttpClientAdapter {
  PreviewAdapter(JsonMap snapshot) : data = jsonMap(jsonDecode(jsonEncode(snapshot)));
  final JsonMap data;
  String account = '静态展示';
  String? siteId;
  final List<JsonMap> labCalls = [], broadcasts = [];
  List<JsonMap> list(String key) => jsonList(data[key]);
  String get userId => idOf(jsonMap(data['identity'])['userId']);
  String get personId => idOf(jsonMap(data['identity'])['personId']);
  List<JsonMap> scoped(String key) => list(key).where((r) {
    if (siteId == null) return true;
    if (key == 'people') return (r['siteIds'] as List? ?? []).contains(siteId);
    return r['siteId'] == null || idOf(r['siteId']) == siteId;
  }).toList();
  JsonMap? find(String key, String id) => list(key).where((r) => idOf(r['id']) == id).firstOrNull;
  JsonMap page(List<JsonMap> rows, RequestOptions o) {
    final current = intOf(o.queryParameters['current'], 1).clamp(1, 99999);
    final size = intOf(o.queryParameters['size'], 20).clamp(1, 500);
    return {'records': rows.skip((current-1)*size).take(size).toList(), 'total': rows.length, 'current': current, 'size': size};
  }
  ResponseBody reply(Object? value, {bool raw = false, int code = 200, String msg = '本地展示操作'}) => ResponseBody.fromString(
    jsonEncode(raw ? value : {'code': code, 'msg': msg, 'data': value}), code,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
  );
  List<JsonMap> equipment(String id) => list('assignments').where((a) => idOf(a['personId'])==id && a['returnedAt']==null && (siteId==null || idOf(a['siteId'])==siteId)).toList();
  DateTime? time(Object? value) => DateTime.tryParse(idOf(value));
  List<JsonMap> tracks(String id, RequestOptions o) {
    final from=time(o.queryParameters['from']),to=time(o.queryParameters['to']);
    final held=list('assignments').where((a)=>idOf(a['personId'])==id && a['typeCode']=='helmet').toList();
    var rows=list('samples').where((r) {
      final at=time(r['occurredAt']);
      if(at==null || r['lat']==null || r['lng']==null || (from!=null && at.isBefore(from)) || (to!=null && at.isAfter(to)))return false;
      return held.any((a)=>a['deviceId']==r['deviceId'] && !at.isBefore(time(a['issuedAt'])!) && (a['returnedAt']==null || at.isBefore(time(a['returnedAt'])!)));
    }).map((r)=>{...r,'sn':find('devices',idOf(r['deviceId']))?['sn']}).toList();
    rows.sort((a,b)=>idOf(a['occurredAt']).compareTo(idOf(b['occurredAt'])));
    if(rows.length>500)rows=List.generate(500,(i)=>rows[(i*(rows.length-1)/499).round()]);
    return rows;
  }
  JsonMap location(JsonMap person) {
    final hat=equipment(idOf(person['id'])).where((d)=>d['typeCode']=='helmet').firstOrNull;
    final samples=list('samples').where((s)=>hat!=null && s['deviceId']==hat['deviceId'] && s['lat']!=null && s['lng']!=null).toList()..sort((a,b)=>idOf(b['occurredAt']).compareTo(idOf(a['occurredAt'])));
    final last=samples.firstOrNull;
    return {'personId':person['id'],'personCode':person['personCode'],'personName':person['name'],'deviceId':hat?['deviceId'],'sn':hat?['sn'],'floor':'unknown','floorSource':'unknown','source':hat==null?'unknown':'helmet','lat':last?['lat'],'lng':last?['lng'],'occurredAt':last?['occurredAt'],'locationQuality':last==null?'unknown':'stale','connectionQuality':hat?['connectionQuality']??'unknown','demo':true};
  }
  List<JsonMap> filterEvents(RequestOptions o) => scoped('events').where((e) {
    for (final k in ['type','personId','taskId','claimantUserId','alarmCode']) {
      final v=idOf(o.queryParameters[k]); if(v.isNotEmpty && idOf(e[k])!=v) return false;
    }
    final status=idOf(o.queryParameters['status']);
    if(status.isEmpty && e['status']=='closed')return false;
    if (status.isNotEmpty && status!='all' && (status=='active' ? e['status']=='closed' : e['status']!=status)) return false;
    for(final entry in {'statuses':'status','types':'type','alarmCodes':'alarmCode','deviceTypes':'deviceType'}.entries) {
      final values=idOf(o.queryParameters[entry.key]);
      if(values.isNotEmpty && !values.split(',').contains(idOf(e[entry.value]))) return false;
    }
    if(idOf(o.queryParameters['escalated'])=='true' && e['escalated']!=true) return false;
    return true;
  }).toList();
  @override Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? stream, Future<void>? cancelFuture) async {
    final p=o.path, body=jsonMap(o.data), parts=p.split('/');
    final write=o.method!='GET';
    if(p=='/captchaImage') return reply({'code':200,'captchaEnabled':true,'uuid':'static-preview'},raw:true);
    if(p=='/login') {account=textOf(body['username']);siteId=null;return reply({'code':200,'token':'local-preview-only'},raw:true);}
    if(p=='/logout') return reply(null);
    if(p=='/api/v1/me') return reply({...jsonMap(data['identity']),'userName':account,'username':account,'currentSiteId':siteId});
    if(p=='/api/v1/me/current-site') {siteId=idOf(body['siteId']);return reply({'currentSiteId':siteId});}
    if(p=='/api/v1/sites') return reply(list('sites'));
    if(p=='/api/v1/me/equipment') return reply(equipment(personId));
    if(p=='/api/v1/events/inbox/count') return reply({'count':scoped('events').where((e)=>e['status']!='closed').length});
    if(p=='/api/v1/duty/summary') {
      final active=scoped('tasks').where((t)=>['ready','in_progress','paused'].contains(t['status'])).toList();
      return reply({'activeTasks':active,'recentEvents':scoped('events').where((e)=>e['status']!='closed').take(8).toList(),'unclaimed':scoped('events').where((e)=>e['status']=='open').length,'peopleCount':scoped('people').length,'deviceCount':scoped('devices').length,'mine':scoped('events').where((e)=>idOf(e['claimantUserId'])==userId).length});
    }
    if(p=='/api/v1/duty/operators') return reply(list('operators'));
    if(p=='/api/v1/duty/handovers') {
      if(write) {final h={...body,'id':'preview-${list('handovers').length}','fromUserId':userId,'siteId':siteId,'status':'pending','createTime':DateTime.now().toIso8601String()};data['handovers']=[h,...list('handovers')];return reply(h);}
      return reply(scoped('handovers'));
    }
    if(p.startsWith('/api/v1/duty/handovers/')) {final h=find('handovers',parts[5]);if(h==null)return reply(null,code:404);h['status']='confirmed';data['handovers']=list('handovers').map((r)=>r['id']==h['id']?h:r).toList();return reply(h);}
    if(p=='/api/v1/people/options') return reply(scoped('people').where((r)=>r['selectable']!=false).toList());
    if(p=='/api/v1/people') {final name=textOf(o.queryParameters['name'],'');return reply(page(scoped('people').where((r)=>textOf(r['name']).contains(name)).toList(),o));}
    if(p.startsWith('/api/v1/people/')) {
      final id=parts[4];
      if(p.endsWith('/equipment'))return reply(equipment(id));
      if(p.endsWith('/assignments'))return reply(list('assignments').where((r)=>idOf(r['personId'])==id).toList());
      return reply(find('people',id));
    }
    if(p=='/api/v1/devices')return reply(page(scoped('devices'),o));
    if(p.startsWith('/api/v1/devices/')) {
      final id=parts[4];
      if(p.endsWith('/calls'))return reply(list('calls').where((r)=>idOf(r['deviceId'])==id).toList());
      if(p.endsWith('/assignments'))return reply(list('assignments').where((r)=>idOf(r['deviceId'])==id).toList());
      if(p.endsWith('/assignment'))return reply(list('assignments').where((r)=>idOf(r['deviceId'])==id && r['returnedAt']==null).firstOrNull);
      if(p.endsWith('/samples') || p.endsWith('/ingest'))return reply([]);
      return reply(find('devices',id));
    }
    if(p=='/api/v1/work-tasks' || p=='/api/v1/work-tasks/mine') {
      final rows=scoped('tasks').where((t) {
        if(p.endsWith('/mine') && idOf(t['ownerUserId'])!=userId && !jsonList(t['members']).any((m)=>idOf(m['personId'])==personId))return false;
        for(final k in ['status','workType']) {final v=idOf(o.queryParameters[k]);if(v.isNotEmpty && t[k]!=v)return false;}
        return true;
      }).toList();return reply(page(rows,o));
    }
    if(p.startsWith('/api/v1/work-tasks/')) {
      final id=parts[4],task=find('tasks',parts[4]);
      if(p.endsWith('/events'))return reply(scoped('events').where((e)=>idOf(e['taskId'])==id).toList());
      if(p.endsWith('/equipment-check')) {
        final checks=<JsonMap>[];
        for(final m in jsonList(task?['members'])) {
          for(final requirement in jsonList(task?['requirements'])) {
            final type=requirement['typeCode'];final item=equipment(idOf(m['personId'])).where((d)=>d['typeCode']==type).firstOrNull;
            checks.add({'personId':m['personId'],'personName':m['name'],'typeCode':type,'sn':item?['sn'],'result':item==null?'missing':(type=='belt'?'unknown':(item['connectionQuality']=='ok'?'ok':'unknown')),'needsConfirm':true});
          }
        }
        return reply(checks);
      }
      if(write && task!=null) {task['status']=switch(parts.last){'start'=>'in_progress','pause'=>'paused','end'=>'ended',_=>task['status']};data['tasks']=list('tasks').map((r)=>r['id']==id?task:r).toList();}
      return reply(task);
    }
    if(p=='/api/v1/events')return reply(page(filterEvents(o),o));
    if(p.startsWith('/api/v1/events/')) {
      final id=parts[4],event=find('events',parts[4]);if(event==null)return reply(null,code:404,msg:'快照中没有此事件');
      if(p.contains('/map-tiles/')) {final tile=jsonMap(data['mapTiles'])[parts.skip(6).join('/')];return tile==null?reply(null,code:404,msg:'此底图未缓存'):reply(tile);}
      if(parts.length==5)return reply(event);
      final action=parts.last;
      if(action=='actions')return reply(list('eventActions').where((r)=>idOf(r['eventId'])==id).toList());
      if(action=='calls')return reply(list('calls').where((r)=>idOf(r['eventId'])==id).toList());
      if(write) {
        final old=event['status'];event['version']=intOf(event['version'])+1;
        if(action=='claim'){event['status']='claimed';event['claimantUserId']=userId;}
        if(action=='handle')event['status']=['sos','fall','impact'].contains(event['type'])?'pending_review':'handling';
        if(action=='close')event['status']='closed';if(action=='reopen')event['status']='open';
        if(action=='task')event['taskId']=body['taskId'];if(action=='transfer')event['claimantUserId']=body['toUserId'];
        data['eventActions']=[...list('eventActions'),{'id':'preview-${event['version']}','eventId':id,'action':action,'actor':account,'reason':body['reason']??body['comment'],'fromStatus':old,'toStatus':event['status'],'createTime':DateTime.now().toIso8601String()}];
        // jsonList returns typed copies, so explicitly commit the local replacement.
        data['events']=list('events').map((r)=>idOf(r['id'])==id?event:r).toList();return reply(event);
      }
    }
    if(p=='/api/v1/lab/state')return reply({'calls':labCalls,'devices':scoped('devices'),'broadcasts':broadcasts});
    if(p=='/api/v1/lab/calls') {
      final ids=(body['deviceIds'] as List? ?? []).map((id)=>id.toString()).toList();
      final call={'id':'preview-call-${labCalls.length+1}','userId':userId,'siteId':siteId,'direction':'outgoing','state':'ringing','video':false,'createdAt':DateTime.now().toIso8601String(),'participants':ids.map((id)=>{'deviceId':id,'sn':find('devices',id)?['sn'],'personName':find('devices',id)?['personName'],'state':'ringing'}).toList()};labCalls.add(call);return reply({'call':call});
    }
    if(p.startsWith('/api/v1/lab/calls/')) {
      final c=labCalls.where((r)=>idOf(r['id'])==parts[5]).firstOrNull;
      if(c==null)return reply(null,code:404);
      if(write && ['end','reject'].contains(parts.last))c['state']='ended';
      return reply({'call':c});
    }
    if(p=='/api/v1/lab/tts' || p=='/api/v1/commands/tts') {
      final result={'id':'preview-tts-${broadcasts.length+1}','status':'accepted','heard':false,'demo':true,'text':body['text'],'recipients':[]};broadcasts.add(result);
      return reply(p.contains('/lab/')?result:[result]);
    }
    if(p=='/api/v1/fences')return reply(page(scoped('fences'),o));
    if(p.startsWith('/api/v1/fences/'))return reply(find('fences',parts[4]));
    if(p=='/api/v1/teams')return reply(scoped('teams'));
    if(p=='/api/v1/spaces')return reply(scoped('spaces'));
    if(p.contains('/tracks'))return reply(page(tracks(parts[5],o),o));
    if(p=='/api/v1/locations/people')return reply(page(scoped('people').map(location).toList(),o));
    if(p.startsWith('/api/v1/locations/people/'))return reply(location(find('people',parts[5])??{}));
    return reply(null,code:404,msg:'静态展示中不执行此项外部操作');
  }
  @override void close({bool force=false}){}
}
