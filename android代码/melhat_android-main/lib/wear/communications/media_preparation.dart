import 'dart:async';

import 'rtc_engine.dart';

/// Owns media acquired before the server is allowed to dial. Cancellation and
/// timeout invalidate late permission/capture results and release late streams.
class RtcMediaPreparation<T extends Object> {
  RtcMediaPreparation({
    required this.requestPermission,
    required this.acquire,
    required this.release,
    this.timeout = const Duration(seconds: 20),
  });

  final Future<bool> Function(bool video) requestPermission;
  final Future<T> Function(bool video) acquire;
  final Future<void> Function(T media) release;
  final Duration timeout;
  int _generation = 0;
  T? _media;
  bool? _video;
  Completer<void>? _cancelled;

  Future<void> prepare({required bool video}) async {
    final cancelling = cancel();
    final generation = _generation;
    await cancelling;
    if (generation != _generation) throw const RtcOperationCancelled();
    final cancelled = Completer<void>();
    _cancelled = cancelled;
    final capturing = () async {
      final allowed = await requestPermission(video);
      if (generation != _generation) throw const RtcOperationCancelled();
      if (!allowed) throw RtcPermissionDenied(video: video);
      final media = await acquire(video);
      if (generation != _generation) {
        await release(media);
        throw const RtcOperationCancelled();
      }
      _media = media;
      _video = video;
    }();
    try {
      await Future.any([capturing, cancelled.future]).timeout(timeout);
      if (generation != _generation) throw const RtcOperationCancelled();
    } on TimeoutException {
      if (generation == _generation) await cancel();
      throw const RtcJoinFailure('麦克风准备超时，未发起呼叫');
    } finally {
      if (identical(_cancelled, cancelled)) _cancelled = null;
    }
  }

  T? take({required bool video}) {
    if (_video != video) return null;
    final media = _media;
    _media = null;
    _video = null;
    return media;
  }

  Future<void> cancel() async {
    ++_generation;
    final pending = _cancelled;
    _cancelled = null;
    // The generation check converts this signal into cancellation. Completing
    // normally avoids an unhandled error when cancel wins before Future.any.
    if (pending != null && !pending.isCompleted) pending.complete();
    final media = _media;
    _media = null;
    _video = null;
    if (media != null) await release(media);
  }
}
