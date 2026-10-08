import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final folder = Directory('build/device-ready-accounts');
  await folder.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) return false;
      await File('${folder.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) => writeResponseData(
      data,
      destinationDirectory: folder.path,
      testOutputFilename: 'result',
    ),
  );
}
