import 'event_models.dart';

class EventActor {
  const EventActor({
    required this.userId,
    required this.roles,
    required this.permissions,
    this.userName = '',
  });
  final String userId;
  final Set<String> roles;
  final Set<String> permissions;
  final String userName;
  bool _can(String value) =>
      permissions.contains(value) || permissions.contains('*:*:*');
  bool get isAdmin =>
      roles.contains('admin') || roles.contains('wear_platform_admin');
  bool get canRead => _can('wear:event:list') || _can('wear:event:query');
  bool get isDuty => _can('wear:event:claim');
  bool get isReviewer => _can('wear:event:review');
  bool get canAssignTask => false;
}

abstract final class EventPolicy {
  // The server authorizes task membership for every returned event and command.
  static bool can(EventCommand command, WearEvent event, EventActor actor) {
    if (!actor.canRead) return false;
    final permission = switch (command) {
      EventCommand.claim => 'events:claim',
      EventCommand.handle => 'events:observe',
      EventCommand.saveVerification || EventCommand.verify => 'events:verify',
      EventCommand.joinAssistance || EventCommand.endAssistance => 'sos:assist',
      _ => '',
    };
    if (event.permissions != null && event.permissions![permission] != true) {
      return false;
    }
    final active = const {
      'open',
      'field_pending',
      'claimed',
      'handling',
    }.contains(event.status);
    switch (command) {
      case EventCommand.claim:
        return actor.isDuty &&
            const {'open', 'field_pending'}.contains(event.status);
      case EventCommand.handle:
        return active && actor._can('wear:event:report');
      case EventCommand.saveVerification:
      case EventCommand.verify:
        return active && actor.isReviewer;
      case EventCommand.joinAssistance:
        return active &&
            event.isSos &&
            (actor._can('wear:sos:assist') ||
                event.permissions == null && actor.isDuty) &&
            event.assistance['state'] != 'ended' &&
            !(event.assistance['members'] as List? ?? []).contains(
              actor.userId,
            );
      case EventCommand.endAssistance:
        return active &&
            event.isSos &&
            (actor._can('wear:sos:assist') ||
                event.permissions == null && actor.isDuty) &&
            const [
              'waiting',
              'accepted',
              'active',
            ].contains(event.assistance['state']);
      case EventCommand.ack:
      case EventCommand.confirm:
      case EventCommand.transfer:
      case EventCommand.close:
      case EventCommand.reopen:
      case EventCommand.assignTask:
        return false;
    }
  }
}
