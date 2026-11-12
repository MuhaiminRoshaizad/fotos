import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

OverlayEntry? _showing;

/// A short message in a pill that drops from the top of the screen, with an
/// optional action such as Undo. It sits above every page and sheet, so it
/// never covers the tab bar or a toolbar. A new toast replaces the last one.
///
/// [failed] marks a message about something that did not work. A message
/// that reports nothing done, such as a hint, passes its own [icon] in
/// place of the tick.
void showToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  bool failed = false,
  IconData? icon,
}) {
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  _dismiss(_showing);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Toast(
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      failed: failed,
      icon: icon,
      onGone: () => _dismiss(entry),
    ),
  );
  _showing = entry;
  overlay.insert(entry);
}

void _dismiss(OverlayEntry? entry) {
  if (entry == null) return;
  if (identical(_showing, entry)) _showing = null;
  if (entry.mounted) entry.remove();
}

class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.failed,
    required this.icon,
    required this.onGone,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool failed;
  final IconData? icon;
  final VoidCallback onGone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.long,
    reverseDuration: AppMotion.short,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c.forward();
    // Long enough to read, and to reach Undo when there is one.
    _timer = Timer(Duration(seconds: widget.actionLabel == null ? 3 : 5), _go);
  }

  Future<void> _go() async {
    _timer?.cancel();
    if (!mounted) return;
    await _c.reverse();
    if (mounted) widget.onGone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool still = MediaQuery.disableAnimationsOf(context);
    final Animation<double> t = CurvedAnimation(
      parent: _c,
      curve: still ? Curves.linear : Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
    final Widget pill = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, maxWidth: 420),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          color: cs.surfaceContainerHighest.withValues(alpha: 0.92),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                widget.icon ??
                    (widget.failed
                        ? CupertinoIcons.exclamationmark_triangle
                        : CupertinoIcons.checkmark_alt),
                size: AppIconSize.dense,
                color: widget.failed ? cs.error : cs.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  widget.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (widget.actionLabel != null)
                TextButton(
                  onPressed: () {
                    widget.onAction?.call();
                    _go();
                  },
                  child: Text(widget.actionLabel!),
                ),
            ],
          ),
        ),
      ),
    );
    return Positioned(
      top: MediaQuery.paddingOf(context).top + AppSpacing.sm,
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedBuilder(
          animation: t,
          builder: (BuildContext context, Widget? child) => Opacity(
            opacity: _c.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, still ? 0 : -72 * (1 - t.value)),
              child: child,
            ),
          ),
          child: GestureDetector(
            // Flick it away upwards.
            onVerticalDragEnd: (DragEndDetails d) {
              if ((d.primaryVelocity ?? 0) < 0) _go();
            },
            child: Semantics(
              liveRegion: true,
              container: true,
              child: Material(
                type: MaterialType.transparency,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.xl),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: pill,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
