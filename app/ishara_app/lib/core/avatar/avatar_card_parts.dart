import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/blink.dart';

// The parts screens lay over the avatar card (prototype `#avatar`): Talk
// and Learn's mission.

/// `#avatar .pill`: [text] with a dot; [on] (`.pill.on`, signing): #C9CFFF
/// text and border, a glowing blinking #8E9CFF dot.
class AvatarPill extends StatelessWidget {
  const new({required this.on, required this.text, super.key});

  final bool on;
  final String text;

  @override
  Widget build(BuildContext context) {
    final fg = on ? const Color(0xFFC9CFFF) : Colors.white;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xB3121318),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? const Color(0x80C9CFFF) : const Color(0x33FFFFFF),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Blink(
              on: on,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? const Color(0xFF8E9CFF) : context.colors.muted,
                  boxShadow: on
                      ? const [
                          BoxShadow(color: Color(0xFF8E9CFF), blurRadius: 8),
                        ]
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: context.text.chip.copyWith(fontSize: 11.5, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// `#avatar .ctl button`: 36 px high (min width 36, padding 0 9), round,
/// rgba(18,19,24,.7) with a white 20 % border; a 5 px larger touch area.
class AvatarCtlButton extends StatelessWidget {
  const new({
    required this.semanticLabel,
    required this.onPressed,
    required this.child,
    super.key,
  });

  final String semanticLabel;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    excludeSemantics: true,
    onTap: onPressed,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Container(
          height: 36,
          constraints: const BoxConstraints(minWidth: 36),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xB3121318),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: child,
        ),
      ),
    ),
  );
}

/// `#avatar .cap`: a dark fade from the bottom; [label] (11 px w800
/// #C9CFFF, uppercase in English) over [child]. [onHeight] gets its height
/// (the avatar keeps its signing space above it: `reframe`). There is one
/// avatar: when its screen is shown again, the height is reported again
/// (another screen's caption may have reframed it meanwhile).
class AvatarCaptionBox extends StatefulWidget {
  const new({
    required this.label,
    required this.child,
    required this.onHeight,
    super.key,
  });

  final String label;
  final Widget child;
  final ValueChanged<double> onHeight;

  @override
  State<AvatarCaptionBox> createState() => _AvatarCaptionBoxState();
}

class _AvatarCaptionBoxState extends State<AvatarCaptionBox> {
  double? _height;
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.valuesOf(context).enabled;
    final h = _height;
    if (shown && !_shown && h != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onHeight(h);
      });
    }
    _shown = shown;
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return ReportHeight(
      onHeight: (h) {
        _height = h;
        widget.onHeight(h);
      },
      child: Semantics(
        container: true,
        liveRegion: true,
        label: label,
        child: Container(
          // padding 16 12 9; rgba(18,19,24,.9) → .55 at 60 % → 0
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 9),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xE6121318), Color(0x8C121318), Color(0x00121318)],
              stops: [0, .6, 1],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Text(
                  ar ? label : label.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: context.text.chip.copyWith(
                    fontSize: ar ? 12 : 11,
                    letterSpacing: ar ? 0 : 11 * .05,
                    color: const Color(0xFFC9CFFF),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              widget.child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Calls [onHeight] with the child's height after each layout that changes
/// it.
class ReportHeight extends SingleChildRenderObjectWidget {
  const new({required this.onHeight, super.child, super.key});

  final ValueChanged<double> onHeight;

  @override
  RenderReportHeight createRenderObject(BuildContext context) =>
      RenderReportHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReportHeight renderObject,
  ) => renderObject.onHeight = onHeight;
}

class RenderReportHeight extends RenderProxyBox {
  new(this.onHeight);

  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(h));
  }
}
