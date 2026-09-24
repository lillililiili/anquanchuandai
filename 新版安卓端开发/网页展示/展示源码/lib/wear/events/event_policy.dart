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
  bool get isDuty => isAdmin;
  bool get isReviewer => isAdmin && _can('wear:event:review');
  bool get canAssignTask => isAdmin && _can('wear:task:edit');
}

abstract final class EventPolicy {
  // The server authorizes task membership for every returned event and command.
  static bool can(EventCommand command, WearEvent event, EventActor actor) {
    final active = const {'open', 'claimed', 'handling'}.contains(event.status);
    switch (command) {
      case EventCommand.ack:
        return actor.isAdmin && actor.canRead && !event.isWarning;
      case EventCommand.claim:
      case EventCommand.transfer:
        return false;
      case EventCommand.handle:
        return actor.canRead && !event.isWarning && active;
      case EventCommand.confirm:
        return actor.canRead && event.isWarning && !event.isClosed;
      case EventCommand.close:
        return actor.isReviewer &&
            event.isEmergency &&
            !(event.source == 'manual_sos' &&
                event.reporterUserId == actor.userId) &&
            event.status == 'pending_review';
      case EventCommand.reopen:
        return actor.isReviewer && !event.isWarning && event.isClosed;
      case EventCommand.assignTask:
        return actor.canAssignTask && event.taskMatch == 'pending';
    }
  }
}
