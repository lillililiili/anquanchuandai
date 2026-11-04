import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/communications_page.dart';
import 'wear_shared_backend_test.dart' show contextData;
import 'wear_session_test.dart' show transport, reply, MemoryCredentials;

void main() {
 test('guardian broadcast preserves explicit durable key through shared adapter', () async {
  final keys=<String>[];
  final api=WearApi(mock:false, dio:transport((r){expect(r.path,'/api/guardian/v1/mobile/broadcast');keys.add(r.data['idempotencyKey']);return reply([{'id':'c','deviceId':'h','status':'queued'}],raw:true);}),token:()=> 'token',siteId:()=> 'site-1',epoch:()=>0);
  final body={'deviceIds':['h'],'recipients':[{'deviceId':'h','personId':'P1','assignmentId':'A1','assignmentVersion':1}],'text':'test','idempotencyKey':'same-request-001'};
  await api.post('/api/v1/commands/tts',data:body);await api.post('/api/v1/commands/tts',data:body);
  expect(keys,['same-request-001','same-request-001']);
  await api.post('/api/v1/commands/tts',data:{...body,'idempotencyKey':'new-request-002'});expect(keys.last,'new-request-002');
 });
 testWidgets('real communications page shows queued and keeps key until explicit new broadcast', (tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize=const Size(430,1100);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final keys=<String>[];
  final fixture=contextData();
  final feature={'deviceId':'RL-H001','personId':'P1','assignmentId':'assignment-1','assignmentVersion':4,'supported':true,'verified':true,'available':true};
  fixture['devices'][0].addAll({'source':'DIRECT_HELMET','active':true,'online':true,'freshness':'CURRENT','sourceTime':DateTime.now().toUtc().toIso8601String(),'capabilities':{'actions':['tts']},'featureStates':{'broadcast':feature}});
  fixture['personEquipmentContext']={'P1':{'personId':'P1','devices':[{'deviceId':'RL-H001','personId':'P1','assignmentId':'assignment-1','assignmentVersion':4}],'features':{'broadcast':feature}}};
  final dio=transport((r){
   if(r.path=='/api/guardian/v1/mobile/context')return reply(fixture,raw:true);
   if(r.path=='/api/guardian/v1/mobile/broadcast'){keys.add(r.data['idempotencyKey']);return reply([{'id':'c1','deviceId':'RL-H001','status':'queued','vendorMsg':'等待发送'}],raw:true);}
   return reply([],raw:true);
  });
  final session=WearSession(mock:false,dio:dio,credentials:MemoryCredentials())..initialized=true..token='test-only'..siteId='site-1'..me={'userId':'actor','admin':true,'permissions':['wear:command:tts','wear:person:list','wear:device:list']};
  addTearDown(session.dispose);
  final router=GoRouter(routes:[GoRoute(path:'/',builder:(_,__)=>const Scaffold(body:CommunicationsPage(personId:'P1',deviceId:'RL-H001',action:'tts')))]);
  addTearDown(router.dispose);
  await tester.pumpWidget(WearScope(session:session,child:MaterialApp.router(routerConfig:router)));await tester.pumpAndSettle();
  final input=find.byWidgetPredicate((w)=>w is TextField&&w.decoration?.hintText=='输入要播报的内容');
  await tester.ensureVisible(input);await tester.enterText(input,'请注意安全');
  Future<void> submit() async {await tester.ensureVisible(find.text('提交播报指令'));await tester.tap(find.text('提交播报指令'));await tester.pumpAndSettle();}
  await submit();expect(keys,hasLength(1));expect(find.textContaining('已排队，等待设备所在节点发送'),findsOneWidget);
  await submit();expect(keys[0],keys[1]);
  await tester.ensureVisible(find.text('新建另一广播'));await tester.tap(find.text('新建另一广播'));await tester.pumpAndSettle();await submit();expect(keys[2],isNot(keys[1]));
  expect(find.textContaining('已播放'),findsNothing);expect(tester.takeException(),isNull);
  await tester.pumpWidget(const SizedBox.shrink());
 });
}
