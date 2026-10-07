import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'data.dart';
import 'events/event_state_store.dart';

abstract interface class CredentialStore {
  Future<String?> read();
  Future<void> write(String? token);
}

class SecureCredentialStore implements CredentialStore {
  final FlutterSecureStorage storage;
  const SecureCredentialStore([this.storage = const FlutterSecureStorage()]);
  @override
  Future<String?> read() => storage.read(key: 'wear.access-token');
  @override
  Future<void> write(String? token) => token == null
      ? storage.delete(key: 'wear.access-token')
      : storage.write(key: 'wear.access-token', value: token);
}

class WearSession extends ChangeNotifier {
  late final WearApi api;
  final CredentialStore credentials;
  JsonMap? me;
  String? token;
  String? siteId;
  int _epoch = 0;
  bool busy = false;
  bool initialized = false;
  String? error;
  bool _disposed = false;
  Future<void> _credentialWrite = Future.value();
  Future<void> Function()? beforeLogout;
  Future<void> Function()? terminateCall;
  final ValueNotifier<int> refreshTick = ValueNotifier(0);
  final ValueNotifier<bool> callActive = ValueNotifier(false);
  WearSession({Dio? dio, CredentialStore? credentials})
    : credentials = credentials ?? const SecureCredentialStore() {
    api = WearApi(
      dio: dio,
      token: () => token,
      siteId: () => siteId,
      epoch: () => _epoch,
      onUnauthorized: expire,
    );
    callActive.addListener(_emit);
  }
  String get userId => idOf(me?['userId']);
  String get scopeKey => '$userId.${siteId ?? "none"}.$_epoch';
  Set<String> get roles =>
      (me?['roles'] as List? ?? []).map((e) => e.toString()).toSet();
  Set<String> get permissions =>
      (me?['permissions'] as List? ?? []).map((e) => e.toString()).toSet();
  bool hasRole(String role) => roles.contains(role);
  bool get isAdmin =>
      me?['admin'] == true ||
      hasRole('admin') ||
      hasRole('wear_platform_admin');
  bool can(String permission) {
    // Personnel records are read-only in Android, including administrator accounts.
    if (permission == 'wear:person:edit') return false;
    if (!isAdmin &&
        !const {
          'wear:site:list',
          'wear:site:select',
          'wear:person:list',
          'wear:person:query',
          'wear:device:list',
          'wear:device:query',
          'wear:task:list',
          'wear:task:query',
          'wear:event:list',
          'wear:event:query',
          'wear:event:report',
          'wear:event:confirm',
          'wear:inspection:check',
          'wear:inspection:report',
        }.contains(permission)) {
      return false;
    }
    return permissions.contains(permission) || permissions.contains('*:*:*');
  }

  bool get isDuty => isAdmin;
  bool get isDutyAdmin => isAdmin;
  bool get canHandover => isAdmin;
  bool get isReviewer => isAdmin;
  List<JsonMap> get sites => jsonList(
    me?['authorizedSites'],
  ).where((e) => e['status'] == null || idOf(e['status']) == '0').toList();
  String get siteName =>
      sites
          .where((e) => idOf(e['id']) == siteId)
          .map((e) => textOf(e['name']))
          .firstOrNull ??
      '选择厂站';

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void requestRefresh() {
    if (!_disposed && me != null) refreshTick.value++;
  }

  void _invalidate() {
    _epoch++;
    api.invalidate();
  }

  // Expiry and a rapid re-login must reach the native keystore in that order.
  Future<void> _saveCredential(String? value) {
    final next = _credentialWrite
        .catchError((_) {})
        .then((_) => credentials.write(value));
    _credentialWrite = next;
    return next;
  }

  void _endSessionCall() {
    final ending = terminateCall?.call();
    if (ending != null) unawaited(ending.catchError((_) {}));
    callActive.value = false;
  }

  Future<void> initialize() async {
    if (busy) return;
    busy = true;
    error = null;
    _emit();
    try {
      token = await credentials.read();
      // Do not trust cached identity or the former plain-text legacy token.
      if (token != null) await _loadIdentity();
    } catch (e) {
      if (e is! StaleSessionException) {
        error = e is WearApiException ? e.message : '无法读取登录状态，请重新登录';
      }
    } finally {
      initialized = true;
      busy = false;
      _emit();
    }
  }

  Future<void> login(
    String username,
    String password, {
    String? code,
    String? uuid,
  }) async {
    if (busy) return;
    busy = true;
    error = null;
    _invalidate();
    _endSessionCall();
    me = null;
    siteId = null;
    token = null;
    _emit();
    try {
      final response = jsonMap(
        await api.request(
          'POST',
          '/login',
          raw: true,
          data: {
            'username': username.trim(),
            'password': password,
            'code': ?code,
            'uuid': ?uuid,
          },
        ),
      );
      final value = idOf(response['token']);
      if (value.isEmpty) throw const WearApiException(502, '登录响应缺少凭据，请联系管理员');
      token = value;
      await _saveCredential(token);
      await _loadIdentity();
    } catch (e) {
      error = e is WearApiException ? e.message : '登录未完成，请稍后重试';
      rethrow;
    } finally {
      busy = false;
      initialized = true;
      _emit();
    }
  }

  Future<void> _loadIdentity() async {
    final identity = jsonMap(await api.get('/api/v1/me'));
    if (idOf(identity['userId']).isEmpty || idOf(identity['status']) != '0') {
      expire();
      throw const WearApiException(401, '账号不可用，请联系管理员');
    }
    me = identity;
    final selected = idOf(identity['currentSiteId']);
    siteId = sites.any((e) => idOf(e['id']) == selected) ? selected : null;
    if (siteId == null && sites.length == 1) {
      final id = idOf(sites.single['id']);
      await api.put('/api/v1/me/current-site', data: {'siteId': id});
      siteId = id;
      me!['currentSiteId'] = id;
    }
  }

  Future<void> selectSite(String id) async {
    if (busy || id == siteId) return;
    if (callActive.value) throw const WearApiException(409, '请先在通讯页结束通话，再切换厂站');
    if (!sites.any((e) => idOf(e['id']) == id)) {
      throw const WearApiException(403, '没有该厂站的访问权限');
    }
    busy = true;
    error = null;
    _invalidate();
    _emit();
    try {
      final result = jsonMap(
        await api.put('/api/v1/me/current-site', data: {'siteId': id}),
      );
      if (idOf(result['currentSiteId']) != id) {
        throw const WearApiException(502, '厂站切换未确认，请重试');
      }
      siteId = id;
      me?['currentSiteId'] = id;
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      _emit();
      requestRefresh();
    }
  }

  void expire() {
    _endSessionCall();
    _invalidate();
    token = null;
    me = null;
    siteId = null;
    error = '登录已过期，请重新登录';
    unawaited(_saveCredential(null).catchError((_) {}));
    _emit();
  }

  Future<void> logout() async {
    if (busy) return;
    if (callActive.value) throw const WearApiException(409, '请先在通讯页结束通话，再退出账号');
    busy = true;
    _emit();
    final oldUser = userId;
    String? logoutWarning;
    try {
      try {
        await beforeLogout?.call().timeout(const Duration(seconds: 3));
      } catch (_) {
        logoutWarning = '本地已退出，推送解绑未确认';
      }
      try {
        await api.post('/logout').timeout(const Duration(seconds: 5));
      } catch (_) {
        logoutWarning = '本地已退出，服务端会话注销未确认';
      }
    } finally {
      _invalidate();
      token = null;
      me = null;
      siteId = null;
      try {
        await SharedPreferencesEventStateStore.revokeUser(oldUser);
        await _saveCredential(null);
        final prefs = await SharedPreferences.getInstance();
        for (final key
            in prefs
                .getKeys()
                .where((key) => key.startsWith('wear.$oldUser.'))
                .toList()) {
          await prefs.remove(key);
        }
        await prefs.remove('user_token');
        await prefs.remove('user_info');
      } finally {
        busy = false;
        error = logoutWarning;
        _emit();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidate();
    refreshTick.dispose();
    callActive.dispose();
    super.dispose();
  }
}

class WearScope extends InheritedNotifier<WearSession> {
  const WearScope({
    super.key,
    required WearSession session,
    required super.child,
  }) : super(notifier: session);
  static WearSession of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WearScope>()!.notifier!;
}
