import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/web_preview/preview_data.dart';

final output = Directory(Platform.environment['PREVIEW_OUTPUT_ROOT']!);
final boundary = GlobalKey();
// Same captcha paint geometry/colors as auth_pages.dart; only provide a real
// font because the test engine otherwise paints its default Ahem blocks.
class CaptureCaptchaPainter extends CustomPainter {
  CaptureCaptchaPainter(this.code);
  final String code;
  @override
  void paint(Canvas canvas,Size size) {
    final noise=Paint()..color=const Color(0x332563EB)..strokeWidth=1;
    for(var i=0;i<6;i++) { canvas.drawLine(Offset(size.width*(.05+i*.15),4),Offset(size.width*(.2+i*.12),size.height-4),noise); }
    const colors=[Color(0xFF16A34A),Color(0xFFEA580C),Color(0xFF2563EB),Color(0xFF7C3AED)];
    for(var i=0;i<code.length;i++) {
      final text=TextPainter(text:TextSpan(text:code[i],style:TextStyle(fontFamily:'NotoPreview',color:colors[i%colors.length],fontSize:size.height*.62,fontWeight:FontWeight.w800,fontStyle:i.isOdd?FontStyle.italic:FontStyle.normal)),textDirection:TextDirection.ltr)..layout();
      final dx=size.width*(.08+i*.22),dy=(size.height-text.height)/2+(i.isEven?-2:3);
      canvas.save();canvas.translate(dx+text.width/2,dy+text.height/2);canvas.rotate((i-1.5)*.12);text.paint(canvas,Offset(-text.width/2,-text.height/2));canvas.restore();
    }
  }
  @override
  bool shouldRepaint(CaptureCaptchaPainter oldDelegate)=>oldDelegate.code!=code;
}
class CaptureAdapter extends PreviewAdapter {
  String mode='';
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? stream, Future<void>? cancelFuture) {
    if (o.path == '/api/v1/devices' && mode == '40') return Future.value(reply(null,code:503,msg:'当前为网络异常展示，请检查网络后重试'));
    if (o.path == '/api/v1/devices' && mode == '41') return Completer<ResponseBody>().future;
    return super.fetch(o,stream,cancelFuture);
  }
}
Future<void> settle(WidgetTester t) async {
  for (var i=0;i<3;i++) {
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
  }
  await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 8));
  InlineSpan fonts(InlineSpan s) {
    if (s is! TextSpan) return s;
    final style = s.style ?? const TextStyle();
    return TextSpan(text:s.text, style: style.fontFamily == 'MaterialIcons' ? style : style.copyWith(fontFamily:'NotoPreview'), children:s.children?.map(fonts).toList(),recognizer:s.recognizer,semanticsLabel:s.semanticsLabel);
  }
  for (final e in find.byType(RichText).evaluate()) {
    final render=e.findRenderObject();
    if (render is RenderParagraph) render.text=fonts(render.text);
  }
  for(final e in find.byType(CustomPaint).evaluate()) {
    final render=e.findRenderObject();
    if(render is RenderCustomPaint && render.painter.runtimeType.toString()=='_CaptchaPainter') {
      render.painter=CaptureCaptchaPainter((render.painter as dynamic).code as String);
    }
  }
  await t.pump();
}

Future<void> tapText(WidgetTester t, String label) async {
  final f = find.text(label);
  if (f.evaluate().isEmpty) throw StateError('Missing text: $label');
  await t.ensureVisible(f.last);
  await settle(t);
  await t.tap(f.last);
  await settle(t);
}

Future<void> capture(WidgetTester t, String id) async {
  final folder = Directory('${output.path}/captures/$id')..createSync(recursive: true);
  final modal = find.byType(AlertDialog).evaluate().isNotEmpty ? find.byType(AlertDialog).last : find.byType(BottomSheet).evaluate().isNotEmpty ? find.byType(BottomSheet).last : null;
  final scrollFinder = modal == null ? find.byType(Scrollable) : find.descendant(of:modal,matching:find.byType(Scrollable));
  final candidates = t.stateList<ScrollableState>(scrollFinder).where((s) => s.position.axis == Axis.vertical && s.position.hasContentDimensions && s.position.maxScrollExtent > 1).toList();
  candidates.sort((a,b) => b.position.viewportDimension.compareTo(a.position.viewportDimension));
  final scroll = candidates.isEmpty || id=='41' ? null : candidates.first;
  if (scroll != null) { scroll.position.jumpTo(0); await settle(t); }
  final frames = <Map<String,dynamic>>[];
  for (var i = 0; i < 30; i++) {
    final box = scroll?.context.findRenderObject() as RenderBox?;
    final top = box?.localToGlobal(Offset.zero).dy ?? 0;
    final height = box?.size.height ?? 616;
    final offset = scroll?.position.pixels ?? 0;
    final max = scroll?.position.maxScrollExtent ?? 0;
    final name = '${(i+1).toString().padLeft(2,'0')}.png';
    await t.runAsync(() async {
      final rb = boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await rb.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${folder.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
    frames.add({'file': name, 'offset':offset, 'max':max, 'top':top, 'height':height});
    if (scroll == null || offset >= max - .5) break;
    scroll.position.jumpTo(math.min(max, offset + math.min(height * .72, 400)));
    await settle(t);
  }
  expect(frames.last['offset'], closeTo(frames.last['max'] as double, 1), reason:'Must reach the bottom');
  File('${folder.path}/capture.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({'id':id,'width':360,'height':616,'pixelRatio':3,'frames':frames}));
  debugPrint('CAPTURE $id ${frames.length} frames; max=${frames.last['max']}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = File('${Directory.current.path}/../../新版安卓端开发/网页展示/site/fonts/NotoSansCJKsc-Regular.otf').readAsBytesSync();
    await (FontLoader('NotoPreview')..addFont(Future.value(ByteData.sublistView(font)))).load();
    await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(font)))).load();
    await (FontLoader('Ahem')..addFont(Future.value(ByteData.sublistView(font)))).load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  final cases = <String, String>{
    '01':'/login', '02':'/login', '03':'/sites', '04':'/workbench',
    '05':'/tasks', '06':'/tasks/301', '07':'/people', '08':'/people/101',
    '09':'/supervision', '10':'/devices', '11':'/devices/201', '12':'/devices/201',
    '13':'/tracks', '14':'/fences', '15':'/fences/501', '16':'/tracks',
    '17':'/communications', '18':'/communications?deviceId=201',
    '19':'/communications?deviceId=201&action=video', '20':'/communications?deviceId=201&action=tts',
    '21':'/communications?deviceId=201', '22':'/events', '23':'/events',
    '24':'/events?eventId=401', '25':'/events?eventId=401', '26':'/events?eventId=402',
    '27':'/events?eventId=401', '28':'/events?eventId=401', '29':'/events?eventId=402',
    '30':'/me', '31':'/me', '32':'/me', '33':'/me', '34':'/me', '35':'/me',
    '36':'/me', '37':'/me', '38':'/me', '39':'/people?name=不存在', '40':'/devices',
    '41':'/devices', '42':'/me',
  };
  for (final entry in cases.entries) {
    testWidgets('capture ${entry.key}', (t) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(360,616);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final adapter = CaptureAdapter()..mode=entry.key;
      if (int.parse(entry.key)>=17 && int.parse(entry.key)<=21) (adapter.devices.first['capabilities'] as Map)['actions']=['intercom','video','tts'];
      if (entry.key == '12') { adapter.devices.first['online'] = 0; adapter.devices.first['connectionQuality'] = 'stale'; }
      if (entry.key == '35') adapter.handovers.add({'id':'preview-handover','fromUserName':'李志远','toUserId':'12','status':'pending','createdAt':'2026-09-18T08:00:00+08:00','summary':'请关注东区巡检任务与待核验事件。'});
      if (entry.key == '28') { adapter.events.first['taskId'] = null; adapter.events.first['taskMatch'] = 'pending'; }
      if (entry.key == '29') { adapter.events.last['status']='claimed';adapter.events.last['claimantUserId']='12'; }
      final session = WearSession(credentials: PreviewCredentials(),dio:Dio(BaseOptions(baseUrl:'https://preview.invalid'))..httpClientAdapter=adapter);
      if (!['01','02'].contains(entry.key)) {
        adapter.siteId = entry.key == '03' ? null : '1';
        session.me = adapter.identity;
        session.me!['permissions']=['*:*:*','wear:call:start','wear:command:tts'];
        session.siteId = adapter.siteId;
        session.token = 'local-preview-only';
        session.initialized = true;
      }
      await t.pumpWidget(RepaintBoundary(key:boundary,child:WearApp(session:session,enableNotifications:false,fontFamily:'NotoPreview')));
      await settle(t);
      if (!['01','02','03'].contains(entry.key)) {
        final router=GoRouter.of(t.element(find.byType(Scaffold).first));
        final number=int.parse(entry.key);
        if((number>=5 && number<=16) || (number>=39 && number<=41)) {
          final parents={'06':'/tasks','08':'/people','11':'/devices','12':'/devices','15':'/fences'};
          if(parents.containsKey(entry.key)) { unawaited(router.push(parents[entry.key]!)); await settle(t); }
          unawaited(router.push(entry.value));
        } else { router.go(entry.value); }
        if(entry.key=='41') { await t.pump(); await t.pump(const Duration(milliseconds:900)); } else { await settle(t); }
      }
      switch(entry.key) {
        case '02': await tapText(t,'忘记密码 / 申请重置  >');
        case '13': await t.tap(find.byKey(const ValueKey('track-preview'))); await settle(t);
        case '16':
          await t.tap(find.byKey(const ValueKey('track-person-picker'))); await settle(t);
          await t.enterText(find.byType(TextField).first,'陈');
          await t.tap(find.byIcon(Icons.search).last);
          await settle(t);
        case '18': await tapText(t,'手机呼叫');
        case '19': await tapText(t,'视频呼叫');
        case '21': await tapText(t,'手机呼叫'); await tapText(t,'结束通话');
        case '23': await tapText(t,'筛选');
        case '24': await tapText(t,'更多处置与记录');
        case '27': await tapText(t,'更多处置与记录'); await tapText(t,'转交');
        case '28': await tapText(t,'更多处置与记录'); await tapText(t,'确认关联任务');
        case '29': await tapText(t,'更多处置与记录');
        case '31': await tapText(t,'我的装备');
        case '32': await tapText(t,'我的装备'); await tapText(t,'绑定历史');
        case '33': case '37': await tapText(t,'查看状态');
        case '34': await tapText(t,'设置');
        case '35': await tapText(t,'设置'); await tapText(t,'确认接班');
        case '36': await tapText(t,'帮助与反馈');
        case '38': await tapText(t,'退出登录');
        case '42': await tapText(t,'切换账号');
      }
      await capture(t,entry.key);
      final error=t.takeException();
      if(false && error != null) {
        File('${output.path}/captures/13/known-issue.txt').writeAsStringSync('$error\n原安卓 TracksPage 在空轨迹时预先构造 _trackBody，_points.length - 1 为 -1，触发 clamp 参数异常。');
      } else { expect(error,isNull); }
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds:1));
      session.dispose();
    });
  }
}

