import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final folder = Directory(
    Platform.environment['WEAR_QA_OUTPUT'] ?? 'build/no-device-walkthrough',
  );
  await folder.create(recursive: true);
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) return false;
      await File('${folder.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) => writeResponseData(
      data == null
          ? null
          : (Map<String, dynamic>.from(data)..remove('screenshots')),
      destinationDirectory: folder.path,
      testOutputFilename: 'result',
    ),
  );
}
