import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/communications/contact_favorites.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ContactFavorites store({
    String server = 'server-a',
    String user = '12',
    String site = '1',
  }) => ContactFavorites(server: server, userId: user, siteId: site);

  test(
    'favorites persist, unpin restores roster order, identities are isolated',
    () async {
      final first = store();
      await first.load();
      await first.toggle('p:2');
      await first.toggle('d:1');
      final reopened = store();
      await reopened.load();
      const contacts = ['p:1', 'p:2', 'd:1', 'p:3'];
      expect(reopened.order(contacts, (key) => key), [
        'p:2',
        'd:1',
        'p:1',
        'p:3',
      ]);
      await reopened.toggle('p:2');
      expect(reopened.order(contacts, (key) => key), [
        'd:1',
        'p:1',
        'p:2',
        'p:3',
      ]);
      for (final isolated in [
        store(user: '13'),
        store(site: '2'),
        store(server: 'server-b'),
      ]) {
        await isolated.load();
        expect(isolated.order(contacts, (key) => key), contacts);
      }
      // A filtered result must not reintroduce a hidden favorite.
      expect(reopened.order(['p:1', 'p:3'], (key) => key), ['p:1', 'p:3']);
    },
  );
}
