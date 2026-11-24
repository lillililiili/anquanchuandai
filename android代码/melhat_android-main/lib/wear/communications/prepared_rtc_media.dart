import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'media_preparation.dart';
import 'rtc_engine.dart';

abstract interface class WearPreparedRtcMedia {
  void usePreparedMedia(MediaStream stream);
}

RtcMediaPreparation<MediaStream> prepareWearMedia() =>
    RtcMediaPreparation<MediaStream>(
      requestPermission: (video) async {
        final permissions = await [
          Permission.microphone,
          if (video) Permission.camera,
        ].request();
        return permissions.values.every((permission) => permission.isGranted);
      },
      acquire: (video) async {
        final stream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': video,
        });
        if (stream.getAudioTracks().isEmpty) {
          await releaseWearMedia(stream);
          throw const RtcJoinFailure('未取得可用麦克风，未发起呼叫');
        }
        return stream;
      },
      release: releaseWearMedia,
    );

Future<void> releaseWearMedia(MediaStream stream) async {
  Object? failure;
  for (final track in stream.getTracks()) {
    try {
      await track.stop();
    } catch (error) {
      failure ??= error;
    }
  }
  try {
    await stream.dispose();
  } catch (error) {
    failure ??= error;
  }
  if (failure != null) throw failure;
}
