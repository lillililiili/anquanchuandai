import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:rolling_intelligence_headband/http/request_options.dart';

class TtsApi {
  /// 创建单播
  static Future<void> createSingleBroadcast({
    required String content,
    required String recipient,
  }) async {
    await http.request(
      ReqOptions(
        path: '/hat/tts/broadcast/single-broadcast',
        method: 'POST',
        params: {'content': content, 'recipient': recipient},
      ),
    );
  }

  /// 创建群播
  static Future<void> createGroupBroadcast({
    required String content,
    required String recipients,
  }) async {
    await http.request(
      ReqOptions(
        path: '/hat/tts/broadcast/group-broadcast',
        method: 'POST',
        params: {'content': content, 'recipients': recipients},
      ),
    );
  }
}
