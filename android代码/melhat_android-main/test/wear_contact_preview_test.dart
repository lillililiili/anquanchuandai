import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wear_comms_entry_test.dart' show openDevice;

// Optional local visual acceptance: uses fixture data, never a live server.
void main() {
  const output = String.fromEnvironment('COMMS_PREVIEW_DIR');
  testWidgets(
    'render communications top, bottom and broadcast for review',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = true);
      await tester.runAsync(() async {
        final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
        for (final family in [
          'Ahem',
          'Roboto',
          'PreviewChinese',
          'Arial',
          'sans-serif',
        ]) {
          await (FontLoader(
            family,
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
        final icons = await File(
          'C:/melhat-runtime/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons)))).load();
      });
      final router = await openDevice(
        tester,
        <RequestOptions>[],
        fontFamily: 'PreviewChinese',
      );
      router.go('/communications');
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(
            image.image,
            tester.element(find.byType(NavigationBar)),
          );
        }
      });
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('wear-communications-list'));
      final scroll = tester.widget<ListView>(list).controller!;
      final favorite = find.byKey(const ValueKey('favorite-p:7'));
      await tester.ensureVisible(favorite);
      await tester.pumpAndSettle();
      expect(favorite.hitTestable(), findsOneWidget);
      expect(tester.widget<IconButton>(favorite).onPressed, isNotNull);
      await tester.tap(favorite);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(favorite).isSelected, isTrue);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('联系人07'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('联系人00'));
      await tester.tap(find.text('联系人00'));
      await tester.pumpAndSettle();
      scroll.jumpTo(0);
      await tester.pumpAndSettle();

      Future<void> capture(String name) async {
        expect(tester.takeException(), isNull);
        final boundary = find
            .ancestor(
              of: find.byType(NavigationBar),
              matching: find.byType(RepaintBoundary),
            )
            .first;
        final render = tester.renderObject<RenderRepaintBoundary>(boundary);
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File(
            '$output/$name.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('communications-top');
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await capture('communications-bottom');
      await tester.tap(find.text('文字播报'));
      await tester.pumpAndSettle();
      await capture('communications-broadcast');
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: output.isEmpty,
  );
}
