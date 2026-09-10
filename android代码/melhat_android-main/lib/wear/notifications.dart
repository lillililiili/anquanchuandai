import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:jpush_flutter/jpush_flutter.dart';
import 'package:jpush_flutter/jpush_interface.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'core.dart';

class WearNotice {
  final String eventId, siteId, notificationId;
  final int version;
  final bool hasUniqueDelivery;
  const WearNotice({
    required this.eventId,
    required this.siteId,
    required this.notificationId,
    this.version = 0,
    this.hasUniqueDelivery = true,
  });
  static WearNotice? parse(Object? value) {
    try {
      var data = jsonMap(value is String ? jsonDecode(value) : value);
      final nested = data['extras'] ?? data['cn.jpush.android.EXTRA'];
      if (nested != null) {
        data = {
          ...data,
          ...jsonMap(nested is String ? jsonDecode(nested) : nested),
        };
      }
      final eventId = idOf(data['eventId']), siteId = idOf(data['siteId']);
      final validId = RegExp(r'^[a-zA-Z0-9_-]{1,128}$');
      if (!validId.hasMatch(eventId) || !validId.hasMatch(siteId)) return null;
      final type = idOf(data['type']);
      if (type.isNotEmpty && type != 'wear.event') return null;
      final version = intOf(data['eventVersion'] ?? data['version']);
      final deliveryId = idOf(
        data['notificationId'] ??
            data['cn.jpush.android.MSG_ID'] ??
            data['msgId'],
      );
      return WearNotice(
        eventId: eventId,
        siteId: siteId,
        version: version,
        hasUniqueDelivery: deliveryId.isNotEmpty || version > 0,
        notificationId: textOf(deliveryId, '$siteId:$eventId:$version'),
      );
    } catch (_) {
      return null;
    }
  }
}

/// WS is foreground-only. Native push needs both provider credentials and the server binding API.
class WearNotifications extends ChangeNotifier with WidgetsBindingObserver {
  final WearSession session;
  final Future<void> Function(WearNotice) openEvent;
  static const _native = MethodChannel('rolling/wear');
  JPushFlutterInterface? _push;
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnect;
  Timer? _poll;
  Timer? _heartbeat;
  DateTime? _lastPong;
  bool _disposed = false, _foreground = true, _binding = false;
  bool _bindAgain = false;
  bool _gettingRegistration = false;
  String _registrationId = '';
  Future<void> _nativeTail = Future.value();
  bool _connecting = false;
  int _socketGeneration = 0;
  String _scope = '', _boundUser = '', _installationId = '';
  bool configured = false,
      permissionGranted = false,
      registered = false,
      socketConnected = false;
  String status = '正在检查接警连接';
  String? error;
  WearNotice? pendingOpen, latest;
  final Set<String> _received = {}, _opened = {};
  bool _opening = false;
  WearNotifications({required this.session, required this.openEvent});

  @visibleForTesting
  factory WearNotifications.withPush({
    required WearSession session,
    required Future<void> Function(WearNotice) openEvent,
    required JPushFlutterInterface push,
    String installationId = 'test-installation',
    String registrationId = 'provider-registration',
  }) => WearNotifications(session: session, openEvent: openEvent)
    .._push = push
    ..configured = true
    .._registrationId = registrationId
    .._installationId = installationId;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  // Native and HTTP lifecycle work share one queue. A logout timeout cannot
  // allow DELETE to overtake a pending binding PUT or stop a newer account.
  Future<T> _nativeOrdered<T>(Future<T> Function() operation) {
    final next = _nativeTail.catchError((_) {}).then((_) => operation());
    _nativeTail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _stopForExpiredSession() async {
    final scope = session.scopeKey;
    await _nativeOrdered(() async {
      if (_disposed || session.me != null || scope != session.scopeKey) return;
      if (_registrationId.isNotEmpty) await _push?.stopPush();
      if (_disposed || session.me != null || scope != session.scopeKey) return;
      await _push?.clearAllNotifications();
    });
  }

  void _prepareRegistration() {
    if (_gettingRegistration ||
        _push == null ||
        _disposed ||
        _registrationId.isNotEmpty) {
      return;
    }
    _gettingRegistration = true;
    // JPush holds this Future until its first RID callback. Do not await it in
    // the lifecycle queue or stop the fresh installation before it registers.
    unawaited(
      _push!
          .getRegistrationID()
          .then((rid) async {
            if (_disposed || rid.isEmpty) return;
            _registrationId = rid;
            await _nativeOrdered(() async {
              if (!_disposed) await _push!.stopPush();
            });
            if (!_disposed) await bind();
          })
          .catchError((_) {
            if (!_disposed) {
              status = '推送注册暂未完成，可稍后重试';
              _emit();
            }
          })
          .whenComplete(() => _gettingRegistration = false),
    );
  }

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    session.addListener(_sessionChanged);
    session.beforeLogout = unbind;
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground && session.me != null && !session.busy) {
        session.requestRefresh();
      }
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      _installationId = prefs.getString('wear.installationId') ?? '';
      if (_installationId.isEmpty) {
        final random = Random.secure();
        _installationId = List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        await prefs.setString('wear.installationId', _installationId);
      }
      if (_disposed) return;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final key = await _native.invokeMethod<String>('pushAppKey') ?? '';
        permissionGranted = await Permission.notification.isGranted;
        if (_disposed) return;
        configured = key.isNotEmpty;
        if (configured) {
          _push = JPush.newJPush();
          _push!.addEventHandler(
            onReceiveNotification: (data) async => receive(data),
            onReceiveMessage: (data) async => receive(data),
            onOpenNotification: (data) async => receive(data, opened: true),
            onConnected: (_) async => bind(),
          );
          _push!.setCollectControl(
            imsi: false,
            mac: false,
            wifi: false,
            bssid: false,
            ssid: false,
            imei: false,
            cell: false,
            gps: false,
          );
          _push!.setGeofenceEnable(enable: false);
          _push!.setDataInsightsEnable(enable: false);
          _push!.setUnShowAtTheForeground(unShow: true);
          _push!.setup(
            appKey: key,
            channel: 'wearable',
            production: kReleaseMode,
            debug: false,
          );
          _prepareRegistration();
          final launch = await _push!.getLaunchAppNotification();
          if (_disposed) return;
          receive(jsonMap(launch), opened: true);
        }
      }
      status = configured ? '等待账号绑定推送' : '未配置推送，仅支持前台接警';
    } catch (_) {
      status = '推送初始化未完成，仅支持前台接警';
    }
    _sessionChanged();
    _emit();
  }

  void _sessionChanged() {
    if (_disposed) return;
    final scope = session.me != null && !session.busy && session.siteId != null
        ? session.scopeKey
        : '';
    if (scope != _scope) {
      _scope = scope;
      _closeSocket();
      latest = null;
      if (scope.isNotEmpty && _foreground) _connect();
    }
    if (session.me == null) {
      registered = false;
      _boundUser = '';
      _received.clear();
      _opened.clear();
      if (_push != null) unawaited(_stopForExpiredSession().catchError((_) {}));
    } else if (!session.busy) {
      unawaited(bind());
      unawaited(_openPending());
    }
    _emit();
  }

  Future<void> requestPermission() async {
    if (kIsWeb) return;
    registered = false;
    permissionGranted = (await Permission.notification.request()).isGranted;
    if (!permissionGranted) status = '通知权限未开启，后台接警受限';
    await bind();
    _emit();
  }

  Future<void> bind() async {
    if (_binding) {
      _bindAgain = true;
      return;
    }
    if (_disposed ||
        !configured ||
        _push == null ||
        session.me == null ||
        session.busy ||
        _installationId.isEmpty) {
      return;
    }
    if (registered && _boundUser == session.userId) return;
    if (_registrationId.isEmpty) {
      _prepareRegistration();
      status = '等待推送通道注册，仅支持前台接警';
      _emit();
      return;
    }
    _binding = true;
    final user = session.userId;
    final scope = session.scopeKey;
    try {
      await _nativeOrdered(() async {
        if (_disposed || scope != session.scopeKey || session.busy) return;
        await _push!.stopPush();
        if (_disposed || scope != session.scopeKey || session.busy) return;
        await session.api.put(
          '/api/v1/me/push-installations/$_installationId',
          data: {
            'provider': 'jpush',
            'registrationId': _registrationId,
            'platform': 'android',
            'appVersion': '1.3.0+7',
            'notificationPermission': permissionGranted ? 'granted' : 'denied',
          },
        );
        if (_disposed || scope != session.scopeKey || session.busy) return;
        // Delivery resumes only after the server confirms the current owner.
        await _push!.resumePush();
        if (_disposed || scope != session.scopeKey || session.busy) return;
        registered = true;
        _boundUser = user;
        status = permissionGranted ? '推送已绑定，锁屏到达待真机验收' : '通知权限未开启，后台接警受限';
      });
    } on WearApiException catch (e) {
      if (e is! StaleSessionException) {
        status = e.code == 404 ? '后台推送接口尚未就绪，仅前台接警' : '推送绑定失败，可重试';
      }
    } catch (_) {
      status = '推送通道暂不可用，可重试';
    } finally {
      _binding = false;
      _emit();
      if (_bindAgain) {
        _bindAgain = false;
        unawaited(bind());
      }
    }
  }

  Future<void> unbind() async {
    // Stop local delivery before waiting for HTTP; a timed-out request must not
    // stop push after a different account has already signed in.
    registered = false;
    _boundUser = '';
    pendingOpen = null;
    latest = null;
    final user = session.userId;
    final scope = session.scopeKey;
    await _nativeOrdered(() async {
      if (_disposed || scope != session.scopeKey || user != session.userId) {
        return;
      }
      if (_registrationId.isNotEmpty) await _push?.stopPush();
      if (_disposed || scope != session.scopeKey || user != session.userId) {
        return;
      }
      await _push?.clearAllNotifications();
      if (_disposed || scope != session.scopeKey || user != session.userId) {
        return;
      }
      if (configured && _installationId.isNotEmpty) {
        await session.api.delete(
          '/api/v1/me/push-installations/$_installationId',
        );
      }
    });
    _emit();
  }

  void receive(Object? data, {bool opened = false}) {
    if (_disposed) return;
    final notice = WearNotice.parse(data);
    if (notice == null) return;
    if (opened) {
      if (notice.hasUniqueDelivery && _opened.contains(notice.notificationId)) {
        return;
      }
      pendingOpen = notice;
      unawaited(_openPending());
    } else if (!notice.hasUniqueDelivery ||
        _received.add(notice.notificationId)) {
      if (_received.length > 200) _received.remove(_received.first);
      if (session.sites.any((site) => idOf(site['id']) == notice.siteId)) {
        latest = notice;
        session.requestRefresh();
      }
    }
    _emit();
  }

  Future<void> _openPending() async {
    if (_opening || pendingOpen == null || session.me == null || session.busy) {
      return;
    }
    _opening = true;
    final notice = pendingOpen!;
    final user = session.userId;
    try {
      if (!session.sites.any((site) => idOf(site['id']) == notice.siteId)) {
        throw const WearApiException(403, '当前账号无权查看该通知');
      }
      await openEvent(notice);
      if (notice.hasUniqueDelivery) _opened.add(notice.notificationId);
      if (_opened.length > 200) _opened.remove(_opened.first);
      error = null;
    } catch (e) {
      error = e is WearApiException ? e.message : '通知详情暂时无法打开，请在事件页查看';
      if (user == session.userId &&
          session.sites.any((site) => idOf(site['id']) == notice.siteId) &&
          !(e is WearApiException && (e.code == 403 || e.code == 404))) {
        // Keep a retry target for offline/409 cases, including a cross-site
        // notification opened while a call is active.
        latest = notice;
      }
    } finally {
      if (identical(pendingOpen, notice)) pendingOpen = null;
      _opening = false;
      _emit();
      if (pendingOpen != null) unawaited(_openPending());
    }
  }

  void openLatest() {
    if (latest != null) {
      pendingOpen = latest;
      unawaited(_openPending());
    }
  }

  void dismissLatest() {
    latest = null;
    error = null;
    _emit();
  }

  Future<void> _connect() async {
    final scope = _scope;
    if (scope.isEmpty ||
        !_foreground ||
        _disposed ||
        _connecting ||
        socketConnected) {
      return;
    }
    _connecting = true;
    final generation = ++_socketGeneration;
    try {
      final base = Uri.parse(session.api.dio.options.baseUrl);
      final uri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path:
            '${base.path.replaceAll(RegExp(r'/$'), '')}/ws/${session.userId}/2',
        queryParameters: {'token': session.token!},
      );
      final socket = WebSocketChannel.connect(uri);
      _socket = socket;
      await socket.ready.timeout(const Duration(seconds: 10));
      if (_disposed ||
          scope != _scope ||
          !_foreground ||
          generation != _socketGeneration) {
        await socket.sink.close();
        return;
      }
      socketConnected = true;
      _lastPong = DateTime.now();
      _emit();
      session.requestRefresh();
      _subscription = socket.stream.listen(
        (data) {
          if (_disposed || generation != _socketGeneration || scope != _scope) {
            return;
          }
          if (data == 'pong') {
            _lastPong = DateTime.now();
          } else {
            receive(data);
          }
        },
        onError: (_) {
          if (generation == _socketGeneration) _scheduleReconnect(scope);
        },
        onDone: () {
          if (generation == _socketGeneration) _scheduleReconnect(scope);
        },
      );
      _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
        if (_disposed || generation != _socketGeneration || scope != _scope) {
          return;
        }
        if (DateTime.now().difference(_lastPong!).inSeconds > 45) {
          _scheduleReconnect(scope);
          return;
        }
        try {
          socket.sink.add('ping');
        } catch (_) {
          _scheduleReconnect(scope);
        }
      });
    } catch (_) {
      if (generation == _socketGeneration) _scheduleReconnect(scope);
    } finally {
      if (generation == _socketGeneration) _connecting = false;
    }
  }

  void _scheduleReconnect(String scope) {
    if (_disposed || scope != _scope || !_foreground) return;
    _closeSocket();
    _emit();
    _reconnect = Timer(const Duration(seconds: 5), _connect);
  }

  void _closeSocket() {
    _socketGeneration++;
    _connecting = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    _reconnect?.cancel();
    _reconnect = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_socket?.sink.close());
    _socket = null;
    socketConnected = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      if (_scope.isNotEmpty && !socketConnected) _connect();
      session.requestRefresh();
      unawaited(_refreshPermission());
    } else {
      _closeSocket();
    }
  }

  Future<void> _refreshPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final granted = await Permission.notification.isGranted;
    if (permissionGranted != granted) {
      registered = false;
      permissionGranted = granted;
    }
    await bind();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _closeSocket();
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(_sessionChanged);
    session.beforeLogout = null;
    super.dispose();
  }
}
