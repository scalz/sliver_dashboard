import 'package:example/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

/// Startup smoke test: the launcher renders and every demo page mounts at
/// least one dashboard without throwing.
void main() {
  final anyDashboard = find.byWidgetPredicate((w) => w is DashboardOverlay);

  Future<void> openDemo(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(anyDashboard, findsWidgets, reason: '"$title" mounted no dashboard');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Sliver Dashboard — Examples'), findsOneWidget);
  }

  testWidgets('launcher lists the demos and each one starts', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Sliver Dashboard — Examples'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(3));

    await openDemo(tester, 'Playground');
    await openDemo(tester, 'Nested grids');
    await openDemo(tester, 'Multi-Sliver Drag & Drop');
  });
}
