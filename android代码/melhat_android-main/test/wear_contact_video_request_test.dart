import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/lab_calls.dart';
import 'package:rolling_intelligence_headband/wear/communications/contact_video_request.dart';
import 'wear_lab_calls_test.dart' show sessionWith, row;
import 'wear_session_test.dart' show reply;

void main() {
  test(
    'video intent waits for connection and opens same call exactly once',
    () async {
      JsonMap current = row();
      final posts = <String>[];
      final errors = <Object>[];
      final session = sessionWith((request) {
        if (request.method == 'POST') {
          posts.add(request.path);
          expect(request.path, '/api/v1/lab/calls/call-1/video');
          expect(request.data, {'enabled': true});
          current = {...current, 'videoEnabled': true};
          return reply(current);
        }
        return reply({
          'calls': [current],
          'devices': [],
        });
      });
      session.me = {
        ...session.me!,
        'roles': ['wear_platform_admin'],
      };
      final model = LabCallsModel(session);
      final intent = ContactVideoRequest(model, errors.add);
      await model.poll();
      intent.watch('call-1');
      await Future<void>.delayed(Duration.zero);
      expect(posts, isEmpty);
      current = row(state: 'connected');
      await model.poll();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await model.poll();
      expect(posts, ['/api/v1/lab/calls/call-1/video']);
      expect(errors, isEmpty);
      intent.dispose();
      model.dispose();
      session.dispose();
    },
  );

  for (final reason in ['ended', 'scope', 'disposed']) {
    test('video intent cancels when $reason', () async {
      JsonMap current = row();
      final posts = <String>[];
      final session = sessionWith((request) {
        if (request.method == 'POST') posts.add(request.path);
        return reply({
          'calls': [current],
          'devices': [],
        });
      });
      session.me = {
        ...session.me!,
        'roles': ['wear_platform_admin'],
      };
      final model = LabCallsModel(session);
      final intent = ContactVideoRequest(model, (error) => fail('$error'));
      await model.poll();
      intent.watch('call-1');
      if (reason == 'disposed') intent.dispose();
      if (reason == 'scope') session.siteId = '2';
      if (reason == 'ended') {
        current = row(state: 'ended');
        await model.poll();
      }
      current = row(state: 'connected');
      await model.poll();
      await Future<void>.delayed(Duration.zero);
      expect(posts, isEmpty);
      if (reason != 'disposed') intent.dispose();
      model.dispose();
      session.dispose();
    });
  }
}
