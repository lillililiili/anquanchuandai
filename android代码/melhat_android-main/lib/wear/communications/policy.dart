import 'models.dart';

class CommunicationsPolicy {
  const CommunicationsPolicy({required this.userId, required this.permissions});

  final String userId;
  final Set<String> permissions;

  bool get canStartCalls => permissions.contains('wear:call:start');
  bool get canSubmitTts => permissions.contains('wear:command:tts');

  bool canStartVoice(CommunicationDevice device) =>
      canStartCalls && device.available('intercom');

  bool canStartVideo(CommunicationDevice device) =>
      canStartCalls &&
      device.available('video_call') &&
      device.available('intercom');

  bool canSendTts(CommunicationDevice device) =>
      canSubmitTts && device.available('tts');

  bool owns(CallSession session) =>
      userId.isNotEmpty && userId == session.requesterUserId;

  bool canReadCredentials(CallSession session) =>
      owns(session) && !session.isTerminal && !session.demo;

  bool canJoin(CallSession session) =>
      canStartCalls &&
      owns(session) &&
      session.status == WearCallStatus.offered &&
      !session.demo;

  bool canEnd(CallSession session) =>
      canStartCalls && owns(session) && !session.isTerminal;
}
