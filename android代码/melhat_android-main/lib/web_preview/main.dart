import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../wear/app.dart';
import 'preview_data.dart';

// Separate entry point: the Android main.dart and production API stay unchanged.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bundle Chinese glyphs with the static site; no Google Fonts dependency.
  final font = await Dio().get<List<int>>(
    Uri.base.resolve('fonts/NotoSansCJKsc-Regular.otf').toString(),
    options: Options(responseType: ResponseType.bytes),
  );
  final fontData = ByteData.sublistView(Uint8List.fromList(font.data!));
  // The preview build also registers this font as the engine's default family.
  await (FontLoader('NotoPreview')..addFont(Future.value(fontData))).load();
  runApp(
    WearApp(
      session: createPreviewSession(),
      enableNotifications: false,
      fontFamily: 'NotoPreview',
    ),
  );
}
