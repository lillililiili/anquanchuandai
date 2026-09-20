import '../core.dart';
import 'models.dart' hide JsonMap;

/// Selecting a person may include belts/watches. Only call-capable devices
/// participate in a voice call; broadcast selection remains independent.
List<CommunicationDevice> callContactDevices(
  Iterable<CommunicationDevice> devices,
) => devices.where((device) => device.supports('intercom')).toList();

/// Categories combine with AND; choices inside one category combine with OR.
class ContactFilters {
  const ContactFilters({
    this.teams = const {},
    this.types = const {},
    this.tasks = const {},
    this.presence = '',
  });
  final Set<String> teams;
  final Set<String> types;
  final Set<String> tasks;
  final String presence;
  bool get isEmpty =>
      teams.isEmpty && types.isEmpty && tasks.isEmpty && presence.isEmpty;
  bool matchesDevice(CommunicationDevice device) =>
      (types.isEmpty || types.contains(device.typeCode)) &&
      (presence.isEmpty || presence == device.online);
  bool matchesPerson(
    PersonOption person,
    Iterable<CommunicationDevice> devices,
    List<JsonMap> work,
  ) {
    if (teams.isNotEmpty && !teams.contains(person.teamId)) return false;
    if (tasks.isNotEmpty &&
        !work.any(
          (task) =>
              tasks.contains(idOf(task['id'])) &&
              jsonList(
                task['members'],
              ).any((member) => idOf(member['personId']) == person.id),
        )) {
      return false;
    }
    if (types.isEmpty && presence.isNotEmpty) {
      final helmet = PersonHelmetStatus(person.id, devices);
      return presence == 'online'
          ? helmet.isOnline
          : helmet.device?.online == 'offline';
    }
    // One same device must satisfy both type and presence.
    return (types.isEmpty && presence.isEmpty) ||
        devices.any((d) => d.personId == person.id && matchesDevice(d));
  }
}

class ContactRoster {
  const ContactRoster(this.people, this.devices, this.tasks);
  final List<PersonOption> people;
  final List<CommunicationDevice> devices;
  final List<JsonMap> tasks;

  static Future<List<JsonMap>> allPages(WearApi api, String path) async {
    final records = <String, JsonMap>{};
    var current = 1;
    while (true) {
      final page = await api.page(path, current: current, size: 100);
      final before = records.length;
      for (final row in page.records) {
        records[idOf(row['id'])] = row;
      }
      if (!page.hasMore) return records.values.toList();
      if (records.length == before) {
        throw const FormatException('分页数据未继续返回，请刷新重试');
      }
      current++;
    }
  }

  static Future<ContactRoster> load(WearApi api, {required bool lab}) async {
    // The call transport may be simulated; business records always belong to
    // the main backend. The lab must write its changes there before reading.
    final people = await allPages(api, '/api/v1/people');
    final devices = await loadDevices(api);
    final tasks = await allPages(api, '/api/v1/work-tasks');
    // Listing DTOs omit membership; hydrate bounded batches, never infer a group.
    final detailed = <JsonMap>[];
    for (var i = 0; i < tasks.length; i += 6) {
      detailed.addAll(
        await Future.wait(
          tasks
              .skip(i)
              .take(6)
              .map(
                (task) async => jsonMap(
                  await api.get('/api/v1/work-tasks/${idOf(task['id'])}'),
                ),
              ),
        ),
      );
    }
    return ContactRoster(
      people
          .where(
            (p) => p['selectable'] != false && p['status']?.toString() != '1',
          )
          .map(PersonOption.fromJson)
          .toList(),
      devices,
      detailed,
    );
  }

  static Future<List<CommunicationDevice>> loadDevices(WearApi api) async {
    final deviceRows = await allPages(api, '/api/v1/devices');
    final devices = <JsonMap>[];
    for (var i = 0; i < deviceRows.length; i += 6) {
      devices.addAll(
        await Future.wait(
          deviceRows
              .skip(i)
              .take(6)
              .map(
                (d) async =>
                    jsonMap(await api.get('/api/v1/devices/${idOf(d['id'])}')),
              ),
        ),
      );
    }
    return devices.map(CommunicationDevice.fromJson).toList();
  }
}

/// Resolve only visible selections and de-duplicate an owner plus their device.
List<CommunicationDevice> selectedContactDevices({
  required Set<String> selectedKeys,
  required Set<String> visibleKeys,
  required List<CommunicationDevice> devices,
  required ContactFilters filters,
}) {
  final selected = selectedKeys.intersection(visibleKeys);
  return <String, CommunicationDevice>{
    for (final d in devices)
      if (filters.matchesDevice(d) &&
          (selected.contains('d:${d.id}') ||
              selected.contains('p:${d.personId}')))
        d.id: d,
  }.values.toList();
}
