import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/events/event_controller.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';
import 'wear_events_controller_test.dart'
    show FakeEventGateway, MemoryEventStateStore;

void main() {
  test(
    'refresh keeps the version of local edits; explicit reload adopts PC draft',
    () async {
      final gateway = FakeEventGateway()
        ..detail = WearEvent.fromJson({
          'id': 'SOS-1',
          'status': 'handling',
          'version': 4,
        });
      final controller = EventController(
        gateway: gateway,
        store: MemoryEventStateStore(),
        scopeKey: 'real.site-1',
        actor: const EventActor(
          userId: 'manager',
          roles: {'admin'},
          permissions: {'wear:event:list', 'wear:event:review'},
        ),
      );
      addTearDown(controller.dispose);
      await controller.select('SOS-1');
      await controller.updateDraft(
        'SOS-1',
        const EventDraft(situation: '手机编辑中的情况'),
      );
      expect(controller.draftFor('SOS-1').baseVersion, 4);
      gateway.detail = WearEvent.fromJson({
        'id': 'SOS-1',
        'status': 'handling',
        'version': 5,
        'verificationDraft': {
          'situation': 'PC 已保存的情况',
          'conclusion': '需现场处理',
          'measures': '保护现场',
        },
      });
      await controller.select('SOS-1');
      expect(controller.selected!.version, 5);
      expect(controller.draftFor('SOS-1').baseVersion, 4);
      expect(controller.draftFor('SOS-1').situation, '手机编辑中的情况');
      await controller.loadLatestDraft();
      expect(controller.draftFor('SOS-1').baseVersion, 5);
      expect(controller.draftFor('SOS-1').situation, 'PC 已保存的情况');
      expect(controller.draftFor('SOS-1').measures, '保护现场');
    },
  );
}
