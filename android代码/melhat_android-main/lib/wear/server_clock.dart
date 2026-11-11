import 'dart:io';

/// Freshness is measured against the API clock, not the phone's wall clock.
/// HTTP Date has second precision, so its final millisecond is the upper bound
/// for reports produced in that same second. Elapsed time remains monotonic.
class ServerClock {
  ServerClock({DateTime Function()? wallNow, Duration Function()? elapsed})
    : _wallNow = wallNow ?? DateTime.now,
      _elapsed = elapsed ?? _stopwatch.elapsedNow;

  static final _stopwatch = _ElapsedClock();
  final DateTime Function() _wallNow;
  final Duration Function() _elapsed;
  DateTime? _anchor;
  Duration? _anchoredAt;
  Duration? _latestRequestStartedAt;

  Duration startRequest() => _elapsed();

  DateTime now() {
    final anchor = _anchor, anchoredAt = _anchoredAt;
    if (anchor == null || anchoredAt == null) return _wallNow();
    final elapsed = _elapsed() - anchoredAt;
    return anchor.add(elapsed.isNegative ? Duration.zero : elapsed);
  }

  bool observeHttpDate(String? value, {Duration? requestStartedAt}) {
    if (value == null || value.trim().isEmpty) return false;
    if (requestStartedAt != null &&
        _latestRequestStartedAt != null &&
        requestStartedAt < _latestRequestStartedAt!) {
      return false;
    }
    final DateTime reported;
    try {
      reported = HttpDate.parse(value).add(const Duration(milliseconds: 999));
    } on HttpException {
      return false;
    }
    // Simultaneous responses can have the same Date or arrive out of order.
    // Neither may roll back an already calibrated freshness clock.
    final current = _anchor == null ? null : now();
    _anchor = current != null && current.isAfter(reported) ? current : reported;
    _anchoredAt = _elapsed();
    if (requestStartedAt != null) _latestRequestStartedAt = requestStartedAt;
    return true;
  }

  void reset() {
    _anchor = null;
    _anchoredAt = null;
    _latestRequestStartedAt = null;
  }
}

class _ElapsedClock {
  final Stopwatch _stopwatch = Stopwatch()..start();
  Duration elapsedNow() => _stopwatch.elapsed;
}

final serverClock = ServerClock();
