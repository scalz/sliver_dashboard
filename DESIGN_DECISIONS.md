> **A Note on the Writing Process**
>
> This document was structured and drafted through a technical interview between the author (who designed the architecture and made the engineering decisions) and an AI writing assistant configured as a technical journalist. Every technical fact, design decision, and engineering challenge described here represents the actual development experience of building `sliver_dashboard`.
> 

# Building a Dashboard Engine on Flutter Slivers

*Why the hard part wasn't the dashboard — and how 1,000 draggable tiles stay fluid on Flutter Web.*

---

## The frustration that started it

Every dashboard project starts the same way: you need a grid where users drag tiles around, resize them, and watch everything reflow. So you go shopping on pub.dev.

I did — and kept hitting the same wall. Even the big-name packages suffered from a lack of maintenance: issues open for years, and performance that fell apart the moment a grid stopped being a toy. Twenty tiles? Fine. A dense layout with live content and a user who drags things aggressively? Jank and rebuild storms.

I don't say this to dunk on anyone. Maintaining an interaction-heavy layout package is genuinely hard. But I had real technical needs, none of the existing options met them, and I decided to build my own.

## Doing my homework in the JS ecosystem

Before writing a line of code, I asked a different question: **who solved this problem best, anywhere?** The answer wasn't in Flutter — it was in JavaScript, where libraries like GridStack.js and React-Grid-Layout have refined dashboard interactions over a decade of production use: the collision cascades, the drag-in/drag-out semantics, the hundred small behaviors that make a grid feel *right*.

So I studied them. Not to port an API one-to-one, but to extract the interaction model — the part users' hands have already learned — and rebuild it idiomatically for Flutter, adding what those libraries never shipped: first-class responsive breakpoints, keyboard accessibility, a minimap, and more.

## The real problem: a deterministic layout engine

What's easy to misunderstood at the start, and what most dashboard packages often misunderstand: the challenge is not "a grid widget." The challenge is **a layout engine that stays deterministic under hundreds of mutations per second.**

Think about what a single drag frame implies. One tile follows the pointer. Its collisions push neighbors, whose collisions push *their* neighbors. A compaction pass pulls everything up. The next pointer event arrives 8 milliseconds later and does it all again — and the result must be **stable**: the same inputs must always produce the same layout, or tiles start "swimming," oscillating between two solutions frame after frame. Every dashboard grid that feels broken feels broken for this exact reason.

So the core of `sliver_dashboard` is not a widget. It's a pure Dart engine — no `BuildContext`, no widgets, just data in, layout out. Collision resolution, compaction strategies (vertical, horizontal, none, or your own), bounds correction, cluster moves for multi-selection: all deterministic, all unit-testable in isolation, all benchmarkable without rendering a single frame.

The key design rule that keeps it deterministic: **drag updates never mutate the layout incrementally.** Every frame recomputes from a pristine snapshot taken when the gesture started. Incremental mutation accumulates floating error in decision-making — order-dependent pushes, hysteresis, swimming. Snapshot recomputation makes every frame a pure function of (initial layout, current pointer cell). It sounds more expensive; it's actually what makes the fast paths possible, as we'll see.

Above the engine sits a controller layer (reactive state, the drag/resize state machines, import/export), and only then the view layer. When something breaks, we know which of the three floors to visit:

```
        Flutter UI (your widgets)
                  |
   SliverDashboard  ·  overlays, gestures      <- view
                  |
   DashboardController  ·  reactive state,
   drag/resize state machines, persistence     <- controller
                  |
   Pure Dart layout engine  ·  collisions,
   compaction, bounds, policies                <- engine
```

If there's one sentence to remember, it's this: **`sliver_dashboard` is not a grid widget. It's a deterministic, testable layout engine that happens to render through Flutter slivers.**

## A sliver, not a widget that owns your screen

The package is called `sliver_dashboard` because the grid is a real sliver. It composes inside a `CustomScrollView` with whatever your app needs — app bars, sticky headers, other slivers, *another dashboard*. You're not handed a monolith that hijacks scrolling; you get a citizen of Flutter's scroll protocol, and viewport virtualization comes with the citizenship: off-screen tiles simply don't exist in the element tree.

This single decision carries a surprising share of the performance story, and it enables the structural features — segmented grids with barrier items, sticky section headers, programmatic scrolling that cooperates with the rest of your scroll view — almost for free.

One reassurance before giving up: **you never have to touch a sliver to use this package.** The default `Dashboard` widget creates and owns its scroll view for you — drop it in a `Scaffold` and you're done. The sliver architecture is about what the package *enables* when you eventually need it (a collapsing app bar above your grid, a list below it, a dashboard among other slivers), not about what it demands from you on day one. If the word "sliver" has ever scared you off, this is precisely a package where you get the benefits without the learning curve.

## Where the performance actually comes from

Let me explain the reasoning rather than list the tricks, because the reasoning is transferable.

The naive architecture — the one you'd write first — rebuilds every visible tile on every drag frame. Layout changed, widgets depend on layout, rebuild. On native it's sluggish; on Flutter Web with the JS renderer — where CPU overhead and event-handling constraints make performance problems surface earliest — it's fatal. The fix is not "optimize the rebuilds." The fix is to make rebuilds *not happen*.

So a tile is split in two. The **shell** — position, size, selection ring, drag chrome — is feather-light and moves on every frame. The **content** — your actual widget, the chart, the video, the form — is built once, parked behind a `RepaintBoundary`, and repainted only when its own *content signature* changes. During a drag, forty tiles reflow and forty shells move; zero user widgets rebuild.

The engine gets the mirror treatment. Recomputing from a snapshot every frame sounds wasteful until you notice most pointer events don't change anything that matters: if the dragged tile's bounding box still maps to the same grid cells as the last event, the entire collision cascade is skipped. A row-indexed structure answers "who collides with this?" without scanning the full layout. And on web specifically, pointer events are throttled before any of this runs, because no renderer survives an unfiltered mouse-move flood.

The methodology I committed: **all performance work is validated on Flutter Web using the JS renderer — the target where performance problems appear first.** If it holds there, native is a formality. The result: with 1,000 items on the grid, scroll, drag and resize stay fluid everywhere — including in the browser-based demo, which I deliberately ship on the worst case so you can judge the worst case. The README carries a benchmark section for some numbers.

## Things that were much harder than I expected

This is the section I wish more package authors wrote, so here's mine.

**The layout lies to you during a drag.** Hit-testing sounds trivial — until you remember that during any drag, the collision cascade is actively pushing tiles *away from the pointer*. Ask the live layout "what's under the cursor?" and the answer changes every frame, because whatever was there has just been shoved aside. Every hover-dependent feature (highlighting a drop target, converting a tile under the cursor into a nested grid) has to hit-test against the *pre-drag snapshot* — the world as it was before the pushes started. The live layout is for rendering; the snapshot is for truth.

**Pointer events stop when the pointer stops.** One feature converts a tile into a nested grid when you *pause* on it mid-drag. Obvious implementation: detect the pause. Except there is no "pause event" — when the pointer stops moving, the event stream simply goes silent. Pause detection means a timer restarted on every move… at which point trackpads and touchscreens betray you, emitting sub-pixel jitter continuously, so the timer never fires. So the restart must be jitter-anchored — only real movement counts. And once the pause freezes the collision pushes, the edge auto-scroll — running on its own 16ms tick — happily re-applies them, fighting the freeze until you shut it down. Three interacting subsystems for one micro-interaction.

**Immutable snapshots and mid-drag mutations don't mix — until they must.** Remember the rule that every drag frame recomputes from a pristine snapshot? It served flawlessly right up to the feature that lets the *application mutate the layout while a drag is in flight* (flagging a tile as a nested-grid host, mid-gesture). The next recompute rebuilt from the snapshot and silently erased the mutation — the freshly created nested grid unmounted with the item that had just been dropped into it. The fix is a write-through: mid-gesture mutations patch the snapshot too. The general lesson stung: **any system that rebuilds state from a snapshot has, somewhere, a mutation path that bypasses the snapshot.** Find it before your users do.

**Cross-grid drag is a small distributed-systems problem.** Dragging a tile out of one grid and into another — possibly nested three levels deep, possibly created milliseconds ago — means multiple independent grids sharing one gesture. Who owns the pointer? What happens if the target grid gets disposed mid-flight, taking its render objects with it? (Answer: never cache a `RenderBox`; resolve it lazily at every use.) What restores the origin grid if the drop is cancelled? The solution is a coordinator with explicit sessions and a hard guarantee: *any* exit — drop, cancel, teardown — restores or finalizes, never leaks. Getting that guarantee took more tests than the happy path did.

**The fastest rebuild is the one you refuse to do.** The content cache has a consequence that looks like a bug and is a contract: changing your `itemBuilder` between frames does *not* rebuild existing tiles. Their content is cached by design; you invalidate a tile's signature explicitly when its meaning changes. Making that a documented API decision — rather than a "sometimes it rebuilds" heuristic — is what keeps rebuilds near zero *predictably*.

**You must never mistake a widget's layout box for its actual visual content boundaries.**
When we extended the engine to support multiple, asymmetrical grids inside the *same* scroll view (Multi-Sliver Drag & Drop), we nested their respective interaction overlays (`DashboardOverlay`). Under the hood, each overlay provided its controller to its subtree via an `InheritedWidget`.

But because the overlays were nested, the innermost provider shadowed the outer one—making both slivers bind to the exact same controller! Even worse, because the overlays were full-screen box widgets wrapping the scroll view, they *both* claimed the pointer was within their bounds during hit-testing. The depth-resolving coordinator always picked the deepest one, causing tiles in Grid 1 to instantly teleport to Grid 2 the millisecond you started dragging them.

The fix required two interventions: allowing slivers to bypass the ancestor lookup by explicitly binding their controller to their build subtree, and teaching the overlays to hit-test against the **Sliver's actual visible paint boundaries** (using scroll offsets and paint extents) rather than their own full-screen box geometries. It was a stark reminder that in complex composited layouts, visual truth lives in the sliver constraints, not the widget box.

## The point I actually wanted to make about Flutter

For years, the "Flutter vs. JS-based stacks debate" has been argued with CRUD apps and hello-world benchmarks. Yes, the web ecosystem has a historical headstart in library density for complex tools—rich like dashboard builders. But that is because a decade of library investment landed there.

That's the gap `sliver_dashboard` is aimed at. Nothing in this article required heroics from the framework — slivers, repaint boundaries, and a pure Dart engine are all ordinary Flutter and ordinary software engineering. Flutter, gives us a raw, native graphics engine (Skia/Impeller) and sliver virtualization out of the box. We aren't negotiating with a browser's layout engine; we are painting directly to the GPU. The performance ceiling was never the framework's.  When you combine Flutter’s direct metal painting with a disciplined, allocation-free Dart engine, you don't just match JS performance—you easily surpass it. So the performance ceiling was ours to claim, one hard component at a time — cross-platform, from a single codebase.

## What's in the box

No need to catalog the API here — the README documents more than twenty-five capabilities, each with a runnable example: nested grids with seamless cross-grid drag & drop, edit mode, external drag sources, drag-to-delete, multi-selection with cluster drag, responsive breakpoints, section barriers, a minimap, a bin-packing layout optimizer, import/export, custom compaction strategies, and keyboard navigation with screen-reader support. Getting started is deliberately boring:

```dart
final controller = DashboardController(
  initialSlotCount: 8,
  initialLayout: const [
    LayoutItem(id: 'sales', x: 0, y: 0, w: 4, h: 2),
    LayoutItem(id: 'traffic', x: 4, y: 0, w: 4, h: 2),
  ],
)..setEditMode(true);

Scaffold(
  appBar: AppBar(title: const Text('My Dashboard')),
  body: Dashboard(
    controller: controller,
    itemBuilder: (context, item) => MyTile(id: item.id),
  ),
);
```

No sliver in sight — `Dashboard` owns its scroll view. Drag, resize, collisions and compaction included; everything else is opt-in. And the day you need a collapsing app bar or a grid mixed with other slivers, the same engine and the same controller are available as a real sliver (`DashboardOverlay` + `SliverDashboard`) — you graduate to the composition API without rewriting anything.

If you've been burned by dashboard grids before, this was built for you: not another grid widget, but an engine you can hold to account. And if you find a case where it doesn't hold up — open an issue, feel free to contribute. Keeping this engine robust and optimized under real-world scenarios is an ongoing priority, and every reported edge case is a welcome opportunity to make the test suite even stronger.
