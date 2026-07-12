import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';

void main() {
  group('DashboardControllerImpl — remaining paths', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1),
          LayoutItem(id: 'b', x: 2, y: 0, w: 2, h: 1),
        ],
      );
    });

    tearDown(() => controller.dispose());

    test('setAllowAutoShrink toggles the beacon', () {
      expect(controller.allowAutoShrink.value, isFalse);
      controller.setAllowAutoShrink(allow: true);
      expect(controller.allowAutoShrink.value, isTrue);
      controller.setAllowAutoShrink(allow: false);
      expect(controller.allowAutoShrink.value, isFalse);
    });

    test('setNestTargetHover sets, no-ops on same value, and clears', () {
      final impl = controller.internal;
      expect(impl.hoveredNestTargetId.value, isNull);

      impl.setNestTargetHover('a');
      expect(impl.hoveredNestTargetId.value, 'a');

      // Same value: no-op (peek fast path).
      impl.setNestTargetHover('a');
      expect(impl.hoveredNestTargetId.value, 'a');

      impl.setNestTargetHover(null);
      expect(impl.hoveredNestTargetId.value, isNull);
    });

    test(
        'placeholderHitTestSnapshot: null without a placeholder, pre-push '
        'snapshot while one is active, null again after hiding', () {
      final impl = controller.internal;
      expect(impl.placeholderHitTestSnapshot, isNull);

      final before = List<LayoutItem>.from(controller.layout.value);
      impl.showPlaceholder(x: 0, y: 0, w: 2, h: 1);

      final snapshot = impl.placeholderHitTestSnapshot;
      expect(snapshot, isNotNull);
      // The snapshot is the pre-push layout: same ids and geometry as before
      // the placeholder started shoving items around.
      expect(
        snapshot!.map((i) => '${i.id}:${i.x},${i.y}').toSet(),
        before.map((i) => '${i.id}:${i.x},${i.y}').toSet(),
      );

      impl.hidePlaceholder();
      expect(impl.placeholderHitTestSnapshot, isNull);
      // Layout restored to the pre-drag state.
      expect(
        controller.layout.value.map((i) => i.id).toSet(),
        before.map((i) => i.id).toSet(),
      );
    });

    test(
        'beginCrossGridExit with CompactType.none resolves collisions '
        'instead of compacting', () {
      controller.setCompactionType(CompactType.none);
      final impl = controller.internal;

      final removed = impl.beginCrossGridExit({'a'});
      expect(removed.single.id, 'a');
      // 'b' stays exactly where it was: none-compaction must not pull it left.
      final b = controller.layout.value.single;
      expect(b.id, 'b');
      expect(b.x, 2);

      impl.finishCrossGridExit(outcome: CrossGridExitOutcome.canceled);
      expect(controller.layout.value.length, 2);
    });

    test('scrollToItem completes harmlessly for an unknown item', () async {
      // Must not hang nor throw: the unknown-id branch returns immediately.
      await controller.scrollToItem('does-not-exist');
    });

    test('scrollToItem completes when no overlay is attached', () async {
      await controller.scrollToItem('a');
    });
  });
}
