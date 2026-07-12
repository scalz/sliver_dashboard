# Sliver Dashboard Examples

This folder contains example applications demonstrating the interactive
features, layouts, and performant rendering capabilities of the
`sliver_dashboard` package.

Launching the app opens a small home screen with two demos:

- **Playground** — the full single-grid showcase (drag, resize, sections,
  mini-map, policies, JSON import/export, stress tests).
- **Nested grids (v2)** — dashboards inside dashboard items, with drag & drop
  between grids, `sizeToContent`, `subGridDynamic`, depth limiting, and
  save/load of the whole tree.

## Features Showcased

### Playground (`DashboardPage`)

- **Sliver Composition**: Integration of the grid alongside a pinned `SliverAppBar` and a standard `SliverList` within a single `CustomScrollView`.
- **Live Edit Mode**: Real-time drag-and-drop of multiple selected tiles and dynamic resizing of widgets.
- **Section Barriers**: Visual segmentation of the grid using dedicated dividers and section headers.
- **Declarative Policies (`CustomDashboardPolicy`)**: Enforcement of custom business rules, such as preventing dynamic cards from colliding with or crossing over section dividers.
- **Interactive Mini-Map**: A miniature viewport bird's-eye view of the dashboard, allowing scrub/scroll synchronization.
- **JSON Import/Export**: On-the-fly serialization and loading of grid layout schemas for easy persistence.
- **Stress Testing**: Instant bulk insertion (+20 or +100 items) to benchmark layout performance across web and mobile targets.

### Nested grids (`NestedExamplePage`)

- **Nested dashboards**: A grid item hosts a full `NestedDashboard`; the demo branches on the declarative `LayoutItem.hasNestedGrid` flag so hosts stay portable.
- **Cross-grid drag & drop**: Drag items between the root grid and the nested grid (and back), with a live push-preview placeholder in whichever grid is hovered.
- **`sizeToContent`**: Toggle between a host that grows/shrinks with its content and a fixed-size host that scrolls internally.
- **`subGridDynamic`**: Hold a dragged item over a plain leaf to turn it into a brand-new nested grid on the fly (its controller is created on demand).
- **Compaction switching**: Change the compaction strategy live across every grid.
- **Save / Load**: Export the whole tree to JSON (shown in the panel) and restore it in one call.

The nested demo also runs standalone:

```bash
flutter run -t lib/nested_example.dart
```

## Running the Examples

### Prerequisites

Verify that Flutter is correctly installed on your machine:

```bash
flutter doctor
```

### Installation & Launch

Navigate to the `example` directory, retrieve the dependencies, and start the application:

```bash
cd example
flutter pub get
flutter run
```

### Recommended Platforms

- **Desktop (Windows, macOS, Linux) or Web**: Ideal for testing responsive behavior with the right-side configuration panel (which collapses into a drawer on narrow screens) and fine-tuning tile dimensions using mouse precision.
- **Mobile (iOS, Android)**: Ideal for testing touch gestures such as long-pressing to initiate dragging.

## Code Structure

- **`main.dart`**: Entry point and demo launcher (`ExampleHome`), plus the Playground (`DashboardPage`) configuring the `DashboardController`, managing responsive states, and composing the layout views.
- **`nested_example.dart`**: The nested grids demo (`NestedExamplePage`) — root and child controllers, a `DashboardNestedScope`, and a config panel matching the Playground's style.
- **`CustomDashboardPolicy`** (in `main.dart`): A subclass of `DashboardPolicy` demonstrating how to lock section headers in place and block dynamic item collisions at runtime.