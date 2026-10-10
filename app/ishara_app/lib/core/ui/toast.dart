import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';

/// The prototype's `say()` toast (`.toast`): a short message near the top
/// (70 px + safe area), centred, at most 86 % wide, shown for 2.4 s with a
/// 0.35 s fade and slide. It sits on the root overlay, so it stays while the
/// screen changes. Screen readers announce it.
void showToast(BuildContext context, String message) {
  final overlay = Overlay.of(context, rootOverlay: true);
  _current?.remove();
  final entry = _ToastEntry(message);
  _current = entry;
  entry.show(overlay);
  unawaited(
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    ),
  );
}

_ToastEntry? _current;

class _ToastEntry {
  new(this.message);

  final String message;
  OverlayEntry? _entry;
  final ValueNotifier<bool> _visible = ValueNotifier(false);
  Timer? _timer;

  void show(OverlayState overlay) {
    _entry = OverlayEntry(
      builder: (context) => _Toast(message: message, visible: _visible),
    );
    overlay.insert(_entry!);
    WidgetsBinding.instance.addPostFrameCallback((_) => _visible.value = true);
    _timer = Timer(const Duration(milliseconds: 2400), () {
      _visible.value = false;
      _timer = Timer(const Duration(milliseconds: 350), remove);
    });
  }

  void remove() {
    _timer?.cancel();
    _entry?.remove();
    _entry = null;
    _visible.dispose();
    if (identical(_current, this)) _current = null;
  }
}

class _Toast extends StatelessWidget {
  const new({required this.message, required this.visible});

  final String message;
  final ValueListenable<bool> visible;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = MediaQuery.paddingOf(context).top + 70;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: ValueListenableBuilder(
          valueListenable: visible,
          builder: (context, on, child) => AnimatedOpacity(
            opacity: on ? 1 : 0,
            duration: const Duration(milliseconds: 350),
            child: AnimatedSlide(
              offset: on ? Offset.zero : const Offset(0, -.3),
              duration: const Duration(milliseconds: 350),
              child: child,
            ),
          ),
          child: Center(
            child: FractionallySizedBox(
              widthFactor: .86,
              child: Center(
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: c.panel,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.line),
                      boxShadow: [
                        BoxShadow(
                          color: c.shadow,
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: context.text.chip.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                        color: c.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
