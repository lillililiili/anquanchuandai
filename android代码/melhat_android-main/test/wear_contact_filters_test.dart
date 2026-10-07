import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/communications/contact_filters.dart';
import 'package:rolling_intelligence_headband/wear/communications/models.dart';
import 'package:rolling_intelligence_headband/wear/api.dart';
import 'wear_session_test.dart' show transport, reply;

void main() {
  test('calling a person excludes non-call-capable bound wearables', () {
    final devices = [
      const CommunicationDevice(
        id: 'helmet',
        sn: 'H',
        personId: '1',
        actions: {'intercom', 'video', 'tts'},
      ),
      const CommunicationDevice(
        id: 'belt',
        sn: 'B',
        personId: '1',
        actions: {'tts'},
      ),
    ];
    expect(callContactDevices(devices).map((d) => d.id), ['helmet']);
    expect(
      devices.length,
      2,
      reason: 'Broadcast and equipment selection remain intact',
    );
  });
  const person = PersonOption(
    id: '1',
    name: '测试人员',
    personCode: 'P1',
    teamId: 'group1',
  );
  const other = PersonOption(
    id: '2',
    name: '人员二',
    personCode: 'P2',
    teamId: 'group2',
  );
  const onlineWatch = CommunicationDevice(
    id: 'w',
    sn: 'W',
    personId: '1',
    typeCode: 'watch',
    online: 'online',
    actions: {},
  );
  const offlineHelmet = CommunicationDevice(
    id: 'h',
    sn: 'H',
    personId: '1',
    typeCode: 'helmet',
    online: 'offline',
    actions: {},
  );
  final tasks = <Map<String, dynamic>>[
    {
      'id': 'task1',
      'members': [
        {'personId': '1'},
      ],
    },
    {
      'id': 'task2',
      'members': [
        {'personId': '2'},
      ],
    },
  ];
  test('online and device type must match the same equipment', () {
    const filter = ContactFilters(types: {'helmet'}, presence: 'online');
    expect(
      filter.matchesPerson(person, [onlineWatch, offlineHelmet], tasks),
      isFalse,
    );
    expect(
      const ContactFilters(
        types: {'watch'},
        presence: 'online',
      ).matchesPerson(person, [onlineWatch, offlineHelmet], tasks),
      isTrue,
    );
    expect(
      const ContactFilters(
        presence: 'online',
      ).matchesPerson(person, [onlineWatch, offlineHelmet], tasks),
      isFalse,
    );
    expect(
      const ContactFilters(
        presence: 'offline',
      ).matchesPerson(person, [onlineWatch, offlineHelmet], tasks),
      isTrue,
    );
  });

  test(
    'multiple online states remain an OR group under the device constraint',
    () {
      const both = ContactFilters(
        types: {'helmet'},
        presences: {'online', 'offline'},
      );
      expect(
        both.matchesPerson(person, [onlineWatch, offlineHelmet], tasks),
        true,
      );
      expect(both.matchesDevice(onlineWatch), false);
      expect(both.matchesDevice(offlineHelmet), true);
      expect(
        const ContactFilters(
          presences: {'online', 'offline'},
        ).matchesPerson(person, [], tasks),
        false,
      );
    },
  );
  test(
    'categories AND and multiple choices OR; actual task membership determines group',
    () {
      const filter = ContactFilters(
        teams: {'group1', 'group2'},
        types: {'helmet', 'watch'},
        tasks: {'task1'},
        presence: 'online',
      );
      expect(
        filter.matchesPerson(person, [onlineWatch, offlineHelmet], tasks),
        isTrue,
      );
      expect(
        filter.matchesPerson(other, [onlineWatch, offlineHelmet], tasks),
        isFalse,
      );
      expect(
        filter.matchesPerson(
          person,
          [onlineWatch],
          [
            {'id': 'task1', 'members': []},
          ],
        ),
        isFalse,
      );
    },
  );
  test(
    'unassigned person appears with no equipment filters; unknown is not offline',
    () {
      expect(const ContactFilters().matchesPerson(person, [], []), isTrue);
      const device = CommunicationDevice(id: 'u', sn: 'U', actions: {});
      expect(
        const ContactFilters(presence: 'offline').matchesDevice(device),
        isFalse,
      );
    },
  );
  test('lab overlays cannot override main-backend state or assignment', () {
    final d = CommunicationDevice.fromJson({
      'id': '1',
      'online': 'offline',
      'typeCode': 'helmet',
      'currentAssignment': {'personId': '1'},
      'capabilities': {
        'actions': ['intercom'],
      },
      'lab': {'deviceId': '1', 'online': true, 'personId': 'other'},
    });
    expect(d.online, 'offline');
    expect(d.personId, '1');
    expect(d.simulatedPresence, isFalse);
    expect(d.supports('intercom'), isTrue);
  });
  test(
    'roster pagination consumes all pages, including more than 200 people',
    () async {
      final requested = <int>[];
      final api = WearApi(
        token: () => null,
        siteId: () => null,
        epoch: () => 0,
        dio: transport((r) async {
          final current = r.queryParameters['current'] as int;
          requested.add(current);
          return reply({
            'records': List.generate(
              current == 3 ? 5 : 100,
              (i) => {'id': '${(current - 1) * 100 + i}'},
            ),
            'total': 205,
            'current': current,
            'size': 100,
          });
        }),
      );
      expect(
        await ContactRoster.allPages(api, '/api/v1/people'),
        hasLength(205),
      );
      expect(requested, [1, 2, 3]);
    },
  );
  test(
    'repeated pagination is an explicit failure, not a silently truncated roster',
    () async {
      final api = WearApi(
        token: () => null,
        siteId: () => null,
        epoch: () => 0,
        dio: transport(
          (r) async => reply({
            'records': [
              {'id': '1'},
            ],
            'total': 200,
            'current': 1,
            'size': 100,
          }),
        ),
      );
      await expectLater(
        ContactRoster.allPages(api, '/api/v1/people'),
        throwsFormatException,
      );
    },
  );
  test(
    'hidden selections cannot become recipients; owner and equipment are deduplicated',
    () {
      expect(
        selectedContactDevices(
          selectedKeys: {'p:1', 'd:w', 'd:h'},
          visibleKeys: {'p:1', 'd:w'},
          devices: [onlineWatch, offlineHelmet],
          filters: const ContactFilters(presence: 'online'),
        ).map((d) => d.id),
        ['w'],
      );
      expect(
        selectedContactDevices(
          selectedKeys: {'p:1', 'd:h'},
          visibleKeys: {},
          devices: [onlineWatch, offlineHelmet],
          filters: const ContactFilters(),
        ),
        isEmpty,
      );
    },
  );
  test(
    'lab-enabled roster reads only main APIs and excludes unavailable people',
    () async {
      final api = WearApi(
        token: () => null,
        siteId: () => null,
        epoch: () => 0,
        dio: transport((r) async {
          expect(r.path, isNot(contains('/lab/')));
          final records = r.path == '/api/v1/people'
              ? [
                  {'id': '1', 'name': '正常', 'status': '0', 'selectable': true},
                  {'id': '2', 'name': '停用', 'status': '1'},
                  {'id': '3', 'name': '不可选', 'selectable': false},
                ]
              : [];
          return reply({
            'records': records,
            'total': records.length,
            'current': 1,
            'size': 100,
          });
        }),
      );
      final roster = await ContactRoster.load(api, lab: true);
      expect(roster.people.map((p) => p.id), ['1']);
    },
  );

  test('person status follows assigned helmet health, not an online watch', () {
    expect(PersonHelmetStatus('1', [onlineWatch]).label, '安全帽未关联');
    expect(
      PersonHelmetStatus('1', [onlineWatch, offlineHelmet]).label,
      '安全帽离线',
    );
    CommunicationDevice helmet(Map<String, dynamic> fields) =>
        CommunicationDevice.fromJson({
          'id': 'h',
          'sn': 'H',
          'typeCode': 'helmet',
          'currentAssignment': {'personId': '1'},
          'online': 1,
          'connectionQuality': 'ok',
          ...fields,
        });
    final normal = helmet({'simulation': true, 'simulationStatus': 'normal'});
    expect(PersonHelmetStatus('1', [normal]).isOnline, isTrue);
    expect(PersonHelmetStatus('1', [normal]).label, '在线');
    final abnormal = helmet({
      'simulation': true,
      'simulationStatus': 'low_battery',
      'simulationStatusLabel': '低电量',
    });
    expect(PersonHelmetStatus('1', [abnormal]).isOnline, isFalse);
    expect(
      const ContactFilters(
        presence: 'online',
      ).matchesPerson(person, [onlineWatch, abnormal], []),
      isFalse,
    );
    expect(PersonHelmetStatus('1', [abnormal]).label, '安全帽低电量');
    expect(
      PersonHelmetStatus('1', [
        helmet({'connectionQuality': 'stale'}),
      ]).label,
      '安全帽数据陈旧',
    );
    expect(
      PersonHelmetStatus('1', [
        helmet({'online': null}),
      ]).label,
      '安全帽状态未知',
    );
    expect(PersonHelmetStatus('other', [normal]).isOnline, isFalse);
  });
}
