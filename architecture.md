# Architecture of `sliver_dashboard`

This document outlines the architecture of the `sliver_dashboard` package. It is intended for developers who wish to contribute to the project or understand its internal workings.

## Guiding Principles

The architecture is built on a foundation of modern, idiomatic Flutter principles:

1.  **Declarative UI:** The view layer is a direct representation of the state. We never manually manipulate widgets.
2.  **Reactive State Management:** State is centralized in a controller and exposed as reactive streams (`Beacons`). The UI listens to these streams and rebuilds automatically.
3.  **Separation of Concerns:** The codebase is cleanly divided into three distinct layers: State, Logic, and View.
4.  **Performance First:**
    *   **Virtualization:** The core view is built on Flutter's `Sliver` protocol to render only visible items.
    *   **Aggressive Caching:** Individual item widgets are cached and protected from unnecessary rebuilds using a "Firewall" widget strategy.
    *   **Paint Isolation:** Use of `RepaintBoundary` ensures that layout changes (moving an item) do not trigger expensive repaints of the item's content.
5.  **Immutability:** State objects, particularly the `LayoutItem` model, are immutable.

## Core Layers

The package is divided into three main layers, each with a distinct responsibility.

```mermaid
graph TD
    subgraph View Layer
        A[Dashboard Widget] --> B[DashboardOverlay];
        B --> C(CustomScrollView);
        B -- "Gestures & Feedback" --> F[Feedback Stack];
        B -- "Background" --> BG[DashboardGrid];
        C --> D(SliverDashboard);
        D --> E(RenderSliverDashboard);
        E --> I["DashboardItem (Cache Firewall)"];
        I --> J["User Content (RepaintBoundary)"];
    end

    subgraph State Layer
        K[DashboardController - Interface] --> L[DashboardControllerImpl]
        L --> M["Beacons (State)"];
    end

    subgraph Logic Layer
        N[LayoutEngine];
    end

    B -- "User Gestures (Drag/Resize)" --> K;
    L -- Updates State --> M;
    M -- Notifies --> B;
    M -- Notifies --> D;
    L -- Calls Pure Functions --> N;
    N -- Returns New Layout --> L;

    style A fill:#cde4ff,color:#000000
    style B fill:#dae8fc,color:#000000
    style D fill:#d5e8d4,color:#000000
    style K fill:#fff2cc,color:#000000
    style N fill:#ffe6cc,color:#000000
```

### 1. The State Layer (DashboardController)

- **Location:** `lib/src/controller/`
- **Responsibility:** To be the single source of truth for the dashboard's state and to expose a clean, public API.
- **Implementation:**
    - **Interface Separation:** The public `DashboardController` is an abstract interface. The logic resides in `DashboardControllerImpl`.
    - **Drag Offset:** Manages a `dragOffset` beacon to provide smooth visual feedback during drags without committing every pixel change to the logical grid layout.
    - **Orchestrator:** It acts as a bridge. When an action occurs (e.g., `onDragUpdate`), it:
        1. Reads the current state.
        2. Calls the pure `LayoutEngine`.
        3. Updates the beacons with the result.

### 2. The Logic Layer (LayoutEngine)

- **Location:** `lib/src/engine/layout_engine.dart`
- **Responsibility:** To perform all pure, CPU-intensive layout calculations.
- **Implementation:**
    - A library of top-level, pure functions (e.g., `compact`, `moveElement`, `resizeItem`).
    - **Decoupled:** Has no knowledge of Flutter widgets or the controller. Operates purely on the `LayoutItem` data model.
    - **Deterministic:** Given the same input layout and parameters, it always returns the same output layout.

### 3. The View Layer (Overlay & Slivers)

- **Location:** `lib/src/view/`
- **Responsibility:** To render the state efficiently and handle user gestures.

The view layer has been refactored to support native Sliver composition. It is composed of three key widgets:

#### A. `DashboardOverlay` (The Interaction Layer)
- **Role:** Handles all user interactions (Gestures), visual feedback (Drag placeholders, Resize handles), Auto-scrolling, and the Trash bin.
- **Placement:** It must wrap the `CustomScrollView`.
- **Logic:**
    - Uses a global `GestureDetector` to track pointer events.
    - Performs hit-testing to locate the underlying `RenderSliverDashboard` and the specific item being interacted with.
    - Manages the `Stack` that displays the **Grid Background** (`DashboardGrid`) and the **Feedback Item** (the widget following the finger).

#### B. `SliverDashboard` (The Rendering Layer)
- **Role:** Renders the actual items within the scroll view using the Sliver protocol.
- **Logic:**
    - **Responsive Logic:** Handles `breakpoints` internally using `SliverLayoutBuilder`.
        - **Optimization:** Uses a "Skip Frame" strategy. If the slot count needs to be updated based on width, it schedules the update via `addPostFrameCallback` and returns `SizedBox.shrink()` for the current frame. This prevents building the heavy grid twice (once with wrong slots, once with correct slots).
    - **RenderObject:** Creates and updates `RenderSliverDashboard`.

#### C. `RenderSliverDashboard` (The Engine Room)
- **Role:** Implements `RenderSliverMultiBoxAdaptor` to perform the actual layout and painting.
- **Virtualization:** Only lays out and paints items that are currently visible in the viewport.
- **Layout Protocol (Critical):** The `performLayout` method manages a **doubly linked list** of children. It strictly follows this sequence to ensure stability:
    1.  **Metrics:** Calculate slot sizes based on constraints and aspect ratio.
    2.  **Garbage Collection:** Remove invisible children *before* insertion to clear invalid references.
    3.  **Initial Child:** Find and insert the first visible item based on scroll offset.
    4.  **Fill Trailing/Leading:** Insert remaining visible items outwards from the initial child.

#### D. Internal Components
- **`DashboardItemWrapper`:**
    - Adds visual decorations needed for editing, such as the **Resize Handles**.
    - Wraps the content in a `GuidanceInteractor` if guidance is enabled.
    - It is part of the cached subtree within `DashboardItem`.
- **`GuidanceInteractor`:**
    - Handles hover (desktop) and tap/long-press (mobile) events to display contextual guidance messages.
    - Manages gesture conflicts on mobile to ensure drag operations are not blocked.

## 4. Performance Optimization Strategy

The biggest challenge in a grid layout is preventing the reconstruction of child widgets when the parent layout changes (e.g., resizing the window or dragging an item). `sliver_dashboard` solves this using a multi-level caching strategy:

1.  **`DashboardItem` (The Firewall):**
    - A `StatefulWidget` that wraps every item in the grid.
    - It maintains a cache of the built widget subtree.
    - **Smart Invalidation:** In `didUpdateWidget`, it compares the `contentSignature` of the new item vs. the old item.
        - `contentSignature` is a hash of properties that affect *content* (width, height, id, static status).
        - **Crucially**, it *ignores* position changes (`x`, `y`) and the `itemBuilder` closure instance.
    - If the signature matches, it returns the **exact same widget instance** from its cache. Flutter detects `oldWidget == newWidget` and stops the rebuild propagation immediately.

2.  **Lazy Loading:**
    - The cache is initialized lazily in the `build()` method (not `initState`). This ensures that `InheritedWidgets` (like `Theme`, `Provider`, or `LiteRefScope`) are accessible during the first build.

3.  **`RepaintBoundary`:**
    - The cached widget tree includes a `RepaintBoundary` wrapping the user's content.
    - When an item is moved (layout update), the GPU can simply translate the existing texture without repainting the pixels of the child widget.

## 5. Core Technical Patterns

### Coordinate Separation
The system strictly separates logical grid coordinates from visual pixel coordinates to maintain precision.
- **Engine:** Operates strictly in **Grid Coordinates** (`int x, y`). It never sees pixel values.
- **View:** Handles translation to **Pixel Coordinates** (`double offset`) using `SlotMetrics`.

### Sliver Coordinate Mapping
When using `SliverDashboard` inside a complex `CustomScrollView` (e.g., with `SliverAppBar`), the grid does not start at pixel (0,0).
- `DashboardOverlay` locates the `RenderSliverDashboard` in the render tree.
- It extracts `constraints.precedingScrollExtent` to calculate the exact visual offset of the grid.
- This ensures that drag feedback and grid lines align perfectly, regardless of scroll position or headers.

### Transactional Drag State (Anti-Drift)
To prevent floating-point rounding errors and position "drift" during drag operations:
- The controller stores the `originalLayoutOnStart` when a gesture begins.
- Every `onDragUpdate` calculates the new position relative to this **initial state**, not the previous frame's state.
- The `dragOffset` beacon handles the smooth visual translation (pixels) separately from the logical grid updates (integers).

### Feedback Layering
When an item is being dragged:
1.  **Grid:** The actual item in the grid acts as a placeholder (or is hidden).
2.  **Overlay:** A visual copy of the item is rendered in the `DashboardOverlay` stack, floating above the scroll view.
3.  **Synchronization:** The overlay follows the finger/mouse, while the grid placeholder snaps to the nearest valid slot.

#### Data Flow during a Drag Operation

```mermaid
sequenceDiagram
    participant User
    participant Overlay as DashboardOverlay
    participant Controller
    participant Engine as LayoutEngine
    participant Sliver as SliverDashboard

    User->>Overlay: Touch Down
    Overlay->>Overlay: Hit Test (Find Item & Sliver)
    Overlay->>Controller: onDragStart(id)

    loop Dragging
        User->>Overlay: Moves finger
        Overlay->>Controller: onDragUpdate(offset)
        Controller->>Engine: moveElement()
        Engine-->>Controller: New Layout
        Controller-->>Overlay: Drag Offset Beacon (Smooth)
        Controller-->>Sliver: Layout Beacon (Grid Snap)
        
        par Update Feedback
            Overlay->>Overlay: Rebuild Feedback Item
        and Update Grid
            Sliver->>Sliver: performLayout (Move items)
        end

        alt Over Trash Area
            Overlay->>Overlay: Detect Trash Hover
        end
    end

    User->>Overlay: Touch Up (Drop)

    alt Dropped on Armed Trash
        Overlay->>Controller: removeItem(id)
    else Dropped on Grid
        Overlay->>Controller: onDragEnd()
        Controller->>Engine: compact() (Finalize)
    end
```