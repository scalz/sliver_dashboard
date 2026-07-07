# Sliver Dashboard Playground

This folder contains a complete playground application demonstrating the interactive features, layouts, and performant rendering capabilities of the `sliver_dashboard` package.

## Features Showcased

- **Sliver Composition**: Integration of the grid alongside a pinned `SliverAppBar` and a standard `SliverList` within a single `CustomScrollView`.
- **Live Edit Mode**: Real-time drag-and-drop of multiple selected tiles and dynamic resizing of widgets.
- **Section Barriers**: Visual segmentation of the grid using dedicated dividers and section headers.
- **Declarative Policies (`CustomDashboardPolicy`)**: Enforcement of custom business rules, such as preventing dynamic cards from colliding with or crossing over section dividers.
- **Interactive Mini-Map**: A miniature viewport bird's-eye view of the dashboard, allowing scrub/scroll synchronization.
- **JSON Import/Export**: On-the-fly serialization and loading of grid layout schemas for easy persistence.
- **Stress Testing**: Instant bulk insertion (+20 or +100 items) to benchmark layout performance across web and mobile targets.

## Running the Playground

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

- **Desktop (Windows, macOS, Linux) or Web**: Ideal for testing responsive behavior with the right-side configuration panel and fine-tuning tile dimensions using mouse precision.
- **Mobile (iOS, Android)**: Ideal for testing touch gestures such as long-pressing to initiate dragging.

## Code Structure

- **`main.dart`**: Single entry point configuring the `DashboardController`, managing responsive states, and composing the layout views.
- **`CustomDashboardPolicy`**: A subclass of `DashboardPolicy` demonstrating how to lock section headers in place and block dynamic item collisions at runtime.