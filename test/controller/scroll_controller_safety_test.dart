import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

void main() {
  group('Programmatic Scroll Invariants', () {
    test('scrollToItem completes immediately if no overlay is listening (prevents await deadlocks)',
        () async {
      final controller = DashboardController(
        initialLayout: [const LayoutItem(id: 'target', x: 0, y: 0, w: 2, h: 2)],
      );

      // Verification: Calling scrollToItem on a detached controller must not hang the future
      // indefinitely when there is no attached overlay listener.
      await expectLater(
        controller.scrollToItem('target').timeout(const Duration(seconds: 1)),
        completes,
      );
    });
  });
}
