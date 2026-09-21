import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/contact_filters.dart';
import 'package:rolling_intelligence_headband/wear/communications/models.dart' show PersonHelmetStatus;
import 'package:rolling_intelligence_headband/web_preview/preview_data.dart';
JsonMap snapshot()=>jsonMap(jsonDecode(File('assets/preview/snapshot.json').readAsStringSync()));
Future<WearSession> signedIn() async {final data=snapshot();final s=createPreviewSession(snapshot:data);await s.login(jsonMap(data['identity'])['userName'] as String,'preview');await s.selectSite('1');return s;}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 test('snapshot contacts keep exact device ownership',() async {
  final s=await signedIn();addTearDown(s.dispose);
  final roster=await ContactRoster.load(s.api,lab:true);
  expect(roster.people.length,greaterThan(10));
  final chen=roster.people.firstWhere((p)=>p.name=='陈建国');
  final hat=PersonHelmetStatus(chen.id,roster.devices).device;
  expect(hat,isNotNull);expect(hat!.sn,'RL-H001');
  expect(jsonList(await s.api.get('/api/v1/me/equipment')).map((e)=>e['sn']),containsAll(['RL-H001','RL-B001']));
 });
 test('pagination, filters and local-only actions',() async {
  final s=await signedIn();addTearDown(s.dispose);
  final a=await s.api.page('/api/v1/events',size:5,query:{'status':'all'});
  final b=await s.api.page('/api/v1/events',size:5,current:2,query:{'status':'all'});
  expect(a.records.length,5);expect(b.records.length,5);
  expect(a.records.map((r)=>r['id']).toSet().intersection(b.records.map((r)=>r['id']).toSet()),isEmpty);
  final id=idOf(a.records.first['id']);await s.api.post('/api/v1/events/$id/claim',data:{});
  expect(jsonMap(await s.api.get('/api/v1/events/$id'))['status'],'claimed');
  await s.selectSite('2');
  final siteB=await s.api.page('/api/v1/events',size:100,query:{'status':'all'});
  expect(siteB.records.every((e)=>e['siteId']=='2'),isTrue);
  final reset=await signedIn();addTearDown(reset.dispose);
  expect(jsonMap(await reset.api.get('/api/v1/events/$id'))['status'],a.records.first['status']);
  await expectLater(s.api.post('/unsupported'),throwsA(isA<WearApiException>()));
 });
 test('historical tracks retain assignment windows and 500-point limit',() async {
  final s=await signedIn();addTearDown(s.dispose);
  final page=await s.api.page('/api/v1/locations/people/10/tracks',size:500,query:{'from':'2000-01-01T00:00:00+08:00','to':'2100-01-01T00:00:00+08:00'});
  expect(page.total,greaterThan(0));expect(page.total,lessThanOrEqualTo(500));
  final held=jsonList(snapshot()['assignments']).where((a)=>a['personId']=='10' && a['typeCode']=='helmet');
  for(final point in page.records) {
   final at=DateTime.parse(point['occurredAt'] as String);
   expect(held.any((a)=>a['deviceId']==point['deviceId'] && !at.isBefore(DateTime.parse(a['issuedAt'] as String)) && (a['returnedAt']==null || at.isBefore(DateTime.parse(a['returnedAt'] as String)))),isTrue);
  }
 });
 testWidgets('phone layout and continuous page scrolling', (tester) async {
  tester.view.physicalSize=const Size(360,616);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final bytes=File('web/fonts/NotoSansCJKsc-Regular.otf').readAsBytesSync();
  await tester.runAsync(()=>(FontLoader('NotoPreview')..addFont(Future.value(ByteData.sublistView(bytes)))).load());
  await tester.runAsync(()=>(FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(bytes)))).load());
  final icons=File('C:/melhat-runtime/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf').readAsBytesSync();
  await tester.runAsync(()=>(FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons)))).load());
  final s=(await tester.runAsync(signedIn))!;final key=GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key:key,child:WearApp(session:s,enableNotifications:false,fontFamily:'NotoPreview')));
  await tester.pumpAndSettle();
  final out=Directory('../同步验收/20260921/页面截图')..createSync(recursive:true);
  Future<void> capture(String name) async {
   await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:200)));
   await tester.pumpAndSettle();expect(tester.takeException(),isNull,reason:name);
   await tester.runAsync(() async {final boundary=key.currentContext!.findRenderObject() as RenderRepaintBoundary;final image=await boundary.toImage(pixelRatio:3);final png=await image.toByteData(format:ui.ImageByteFormat.png);File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());image.dispose();});
  }
  for(final entry in [('现场','01-现场'),('通讯','02-通讯'),('消息','03-消息'),('我的','04-我的')]) {
   await tester.tap(find.descendant(of:find.byType(NavigationBar),matching:find.text(entry.$1)));
   await tester.pumpAndSettle();await capture('${entry.$2}-顶部');
   final scroll=find.byType(Scrollable).hitTestable();
   if(scroll.evaluate().isNotEmpty){await tester.drag(scroll.last,const Offset(0,-450));await capture('${entry.$2}-下部');}
  }
  await tester.pumpWidget(const SizedBox.shrink());s.dispose();await tester.pump();
 });
}
