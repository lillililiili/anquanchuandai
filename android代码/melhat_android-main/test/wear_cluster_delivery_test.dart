import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/communications/models.dart';
void main() {
 test('durable delivery states stay distinct from confirmed playback', () {
  final cases = {'queued':TtsCommandStatus.queued,'dispatching':TtsCommandStatus.dispatching,'sent':TtsCommandStatus.sent,'acknowledged':TtsCommandStatus.acknowledged,'rejected':TtsCommandStatus.rejected,'expired':TtsCommandStatus.expired,'cancelled':TtsCommandStatus.cancelled,'failed_before_send':TtsCommandStatus.failedBeforeSend,'unknown':TtsCommandStatus.unknown};
  for(final entry in cases.entries) {
   final command=TtsCommand.fromJson({'id':'c','deviceId':'h','status':entry.key,'deliveryReason':'reason'});
   expect(command.status,entry.value);expect(command.vendorMessage,'reason');
   expect(command.status.label,isNot(contains('已播放')));
  }
  expect(TtsCommandStatus.queued.unresolved,isTrue);
  expect(TtsCommandStatus.sent.unresolved,isTrue);
  expect(TtsCommandStatus.unknown.label,contains('不会自动重复下发'));
 });
}
