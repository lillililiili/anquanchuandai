import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A presentation preference, isolated by backend, account and station.
class ContactFavorites {
  ContactFavorites({
    required String server,
    required String userId,
    required String siteId,
  }) : storageKey =
           'wear.contact-favorites.v1.${jsonEncode([server, userId, siteId])}';

  final String storageKey;
  Set<String> _keys = {};

  bool contains(String key) => _keys.contains(key);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _keys = (prefs.getStringList(storageKey) ?? const <String>[]).toSet();
  }

  Future<void> toggle(String key) async {
    final next = {..._keys};
    if (!next.add(key)) next.remove(key);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList(storageKey, next.toList())) {
      throw StateError('Contact favorites could not be saved');
    }
    _keys = next;
  }

  /// Stable partition: favorites retain the roster order within their group.
  List<T> order<T>(Iterable<T> contacts, String Function(T) keyOf) {
    final pinned = <T>[];
    final remaining = <T>[];
    for (final contact in contacts) {
      (contains(keyOf(contact)) ? pinned : remaining).add(contact);
    }
    return [...pinned, ...remaining];
  }
}
