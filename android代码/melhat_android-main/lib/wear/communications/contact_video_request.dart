import 'dart:async';

import '../core.dart';
import 'lab_calls.dart';

/// Opens the existing one-way helmet view after the same voice call connects.
/// Never creates a second call or changes the invitation protocol.
class ContactVideoRequest {
  ContactVideoRequest(this.model, this.onError);

  final LabCallsModel model;
  final void Function(Object) onError;
  String? _callId;
  String? _scope;
  bool _disposed = false;

  void watch(String callId) {
    cancel();
    _callId = callId;
    _scope = model.session.scopeKey;
    model.addListener(_changed);
    _changed();
  }

  void _changed() {
    final id = _callId;
    if (_disposed || id == null) return;
    if (_scope != model.session.scopeKey) {
      cancel();
      return;
    }
    if (!model.fresh || model.busy) return;
    final call = model.call(id);
    if (call == null || !labCallActive(call) || call['videoEnabled'] == true) {
      cancel();
      return;
    }
    if (call['state'] != 'connected' ||
        !jsonList(call['participants']).any((p) => p['state'] == 'connected')) {
      return;
    }
    final scope = _scope;
    cancel();
    // Defer mutation until the model has finished notifying its listeners.
    scheduleMicrotask(() async {
      if (_disposed || model.session.scopeKey != scope) return;
      try {
        await model.setVideo(id, enabled: true);
      } catch (error) {
        if (!_disposed && model.session.scopeKey == scope) onError(error);
      }
    });
  }

  void cancel() {
    model.removeListener(_changed);
    _callId = null;
    _scope = null;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
