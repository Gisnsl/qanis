import 'package:flutter/material.dart';
import 'package:qanis/ui/component/utils.dart';

///悬浮小窗口
class FloatingWindowManager {
  static final FloatingWindowManager _instance = FloatingWindowManager._();

  factory FloatingWindowManager() => _instance;

  FloatingWindowManager._();

  ///浮窗
  OverlayEntry? overlayEntry;

  bool get isShow => overlayEntry != null;

  void show(BuildContext context, {required Widget widget}) {
    if (overlayEntry == null) {
      // var floatingWindow = FloatingWindow(top: 160, left: 210, child: Material(child: child));
      overlayEntry = OverlayEntry(
        builder: (BuildContext context) {
          return widget;
        },
      );
      Overlay.of(context).insert(overlayEntry!);
    }
  }

  ///关闭小窗
  void hide() {
    overlayEntry?.remove();
    overlayEntry = null;
  }
}

/// 可拖拽浮窗容器。
/// Reqable 风格：圆角 12 的暗色面板 + 1px 描边 + 柔和投影，拖拽/边界限制行为保持不变。
class FloatingWindow extends StatefulWidget {
  final Widget child;
  final double top;
  final double right;

  const FloatingWindow({super.key, required this.child, required this.top, required this.right});

  @override
  State<FloatingWindow> createState() => _FloatingWindowState();
}

class _FloatingWindowState extends State<FloatingWindow> with TickerProviderStateMixin {
  double right = 0;
  double top = 0;

  double maxX = 0;
  double maxY = 0;

  /// 拖拽中不做位置动画，松手吸附时才过渡
  bool _dragging = false;

  var parentKey = GlobalKey();
  var childKey = GlobalKey();

  var parentSize = const Size(0, 0);
  var childSize = const Size(0, 0);

  void changeState() {
    setState(() {});
  }

  @override
  void initState() {
    right = widget.right;
    top = widget.top;
    WidgetsBinding.instance.addPostFrameCallback((d) {
      parentSize = getWidgetSize(parentKey);
      childSize = getWidgetSize(childKey);
      maxX = parentSize.width - childSize.width;
      maxY = parentSize.height - childSize.height;
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: parentKey,
      fit: StackFit.expand,
      children: [
        AnimatedPositioned(
          key: childKey,
          right: right,
          top: top,
          duration: _dragging ? Duration.zero : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) {
              setState(() => _dragging = true);
            },
            onPanUpdate: (d) {
              var delta = d.delta;
              setState(() {
                right -= delta.dx;
                top += delta.dy;
              });
            },
            onPanEnd: (d) {
              setState(() {
                _dragging = false;
                right = getValue(right, maxX);
                top = getValue(top, maxY);
              });
            },
            child: _panel(widget.child),
          ),
        ),
      ],
    );
  }

  /// Reqable 面板外观：panel 底、12 圆角、border 描边、柔和投影，内容按圆角裁剪
  Widget _panel(Widget child) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DarkPalette.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DarkPalette.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 18,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  ///限制边界
  double getValue(double value, double max) {
    if (value < 0) {
      return 0;
    } else if (value > max) {
      return max;
    } else {
      return value;
    }
  }

  Size getWidgetSize(GlobalKey key) {
    final RenderBox renderBox = key.currentContext?.findRenderObject() as RenderBox;
    return renderBox.size;
  }
}
