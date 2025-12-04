import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_provider.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/guidance/dashboard_guidance.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';

/// A widget that detects user interactions (hover, tap, long-press)
/// and displays contextual guidance messages.
class GuidanceInteractor extends StatefulWidget {
  /// Creates a [GuidanceInteractor].
  const GuidanceInteractor({
    required this.item,
    required this.child,
    super.key,
  });

  /// The layout item associated with this interactor, containing metadata
  /// such as id, position, size, and interaction flags (isStatic, isResizable).
  final LayoutItem item;

  /// The child widget that this interactor wraps and monitors for user interactions.
  final Widget child;

  @override
  State<GuidanceInteractor> createState() => _GuidanceInteractorState();
}

class _GuidanceInteractorState extends State<GuidanceInteractor> {
  late DashboardController _dashboardController;
  late DashboardGuidance? _messages;
  OverlayEntry? _overlayEntry;

  // Create a LayerLink to connect the widget and the overlay
  final LayerLink _layerLink = LayerLink();

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dashboardController = DashboardControllerProvider.of(context);
    _messages = _dashboardController.guidance;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  void _show(String message, {Alignment alignment = Alignment.topCenter, Duration? duration}) {
    _hide(); // Hide any existing message

    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox) return;

    final position = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: position.dx,
          top: position.dy,
          child: IgnorePointer(
            ignoring: true,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              // Anchor: Bottom of message to Top of item (unless centered)
              targetAnchor: alignment == Alignment.center ? Alignment.center : Alignment.topCenter,
              followerAnchor:
                  alignment == Alignment.center ? Alignment.center : Alignment.bottomCenter,
              // Offset: Add slight padding (e.g., 10px above)
              offset: alignment == Alignment.center ? Offset.zero : const Offset(0, -10),
              child: Material(
                type: MaterialType.transparency,
                // Align ensures the child doesn't stretch to fill the overlay constraints
                child: Align(
                  alignment: Alignment.center,
                  child: _buildMessageBubble(context, message),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);

    if (duration != null) {
      Future.delayed(duration, _hide);
    }
  }

  void _hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildMessageBubble(BuildContext context, String message) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fontSize = _isMobile ? 16.0 : 14.0;
    final padding = _isMobile
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 8);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[300] : Colors.grey[800],
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            message,
            style: TextStyle(
              color: isDark ? Colors.black : Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_dashboardController.isEditing.value || widget.item.isStatic) {
      return widget.child;
    }

    // Wrap the child in CompositedTransformTarget
    final content = CompositedTransformTarget(
      link: _layerLink,
      child: widget.child,
    );

    if (_isMobile) {
      return GestureDetector(
        onTap: _handleTap,
        child: content,
      );
    } else {
      return MouseRegion(
        onHover: (event) => _handleHover(true, event: event),
        onExit: (_) => _handleHover(false),
        child: content,
      );
    }
  }

  void _handleTap() {
    final messages = _messages;
    if (messages == null) return;
    _show(
      widget.item.isResizable ?? true ? messages.tapToResize : messages.tapToMove,
      duration: const Duration(seconds: 2),
    );
  }

  void _handleHover(bool isHovering, {PointerHoverEvent? event}) {
    final messages = _messages;
    if (messages == null) return;
    if (!isHovering || event == null) {
      _hide();
      return;
    }

    final activeId = _dashboardController.activeItemId.peek();
    // action in progress (drag, resize)
    if (activeId != null) {
      if (activeId == widget.item.id) {
        _show(messages.moving.message);
      }
      return;
    }

    // Hover
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPosition = renderBox.globalToLocal(event.position);

    final handle = calculateResizeHandle(
      localPosition: localPosition,
      size: renderBox.size,
      handleSide: _dashboardController.resizeHandleSide.peek(),
      isResizable: widget.item.isResizable ?? true,
    );

    final InteractionGuidance guidance;
    if (handle == null) {
      guidance = messages.move;
    } else {
      switch (handle) {
        case ResizeHandle.left:
        case ResizeHandle.right:
          guidance = messages.resizeX;
        case ResizeHandle.top:
        case ResizeHandle.bottom:
          guidance = messages.resizeY;
        case ResizeHandle.topLeft:
          guidance = messages.resizeTopLeft;
        case ResizeHandle.topRight:
          guidance = messages.resizeTopRight;
        case ResizeHandle.bottomLeft:
        case ResizeHandle.bottomRight:
          guidance = messages.resizeXY;
      }
    }

    _show(guidance.message);
  }
}
