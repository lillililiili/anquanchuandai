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

  bool _can(String permission) =>
      permissions.contains(permission) || permissions.contains('*:*:*');

  bool get canRead => _can('wear:event:list') || _can('wear:event:query');

  bool get isDuty =>
      _can('wear:event:claim') &&
      (roles.contains('wear_duty') || roles.contains('wear_team_lead'));

  bool get isReviewer =>
      _can('wear:event:review') &&
      (roles.contains('wear_reviewer') ||
          roles.contains('wear_platform_admin') ||
          roles.contains('admin'));

  bool get canAssignTask =>
      _can('wear:task:edit') &&
      (roles.contains('wear_duty') || roles.contains('wear_team_lead'));
}

abstract final class EventPolicy {
  static bool can(EventCommand command, WearEvent event, EventActor actor) {
    switch (command) {
      case EventCommand.ack:
        return actor.canRead;
      case EventCommand.claim:
        return actor.isDuty && event.status == 'open';
      case EventCommand.handle:
        return actor.isDuty &&
            event.claimantUserId == actor.userId &&
            const {'claimed', 'handling'}.contains(event.status);
      case EventCommand.transfer:
        return actor.isDuty &&
            event.claimantUserId == actor.userId &&
            const {'claimed', 'handling'}.contains(event.status);
      case EventCommand.close:
        if (event.isHighRisk) {
          return actor.isReviewer && event.status == 'pending_review';
        }
        return actor.isDuty && event.status == 'handling';
      case EventCommand.reopen:
        return actor.isReviewer && event.status == 'closed';
      case EventCommand.assignTask:
        return actor.canAssignTask && event.taskMatch == 'pending';
    }
  }
}
