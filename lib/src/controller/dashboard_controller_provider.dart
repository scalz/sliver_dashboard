import 'package:flutter/widgets.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller.dart';

/// An InheritedWidget that provides a [DashboardController] to its descendants.
///
/// This is used to make the controller available to widgets deep in the tree
/// (like the DashboardItemWrapper) without needing to pass it down manually.
class DashboardControllerProvider extends InheritedWidget {
  /// Creates a provider for a [DashboardController].
  const DashboardControllerProvider({
    required this.controller,
    required super.child,
    super.key,
  });

  /// The controller instance to provide.
  final DashboardController controller;

  /// Retrieves the closest [DashboardController] instance from the widget tree.
  static DashboardController of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<DashboardControllerProvider>();
    assert(provider != null, 'No DashboardControllerProvider found in context');
    return provider!.controller;
  }

  @override
  bool updateShouldNotify(DashboardControllerProvider oldWidget) {
    // The controller is stateful and manages its own listeners, so we don't
    // need the InheritedWidget to notify descendants when the instance changes.
    return controller != oldWidget.controller;
  }
}
