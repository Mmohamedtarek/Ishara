import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ishara_app/core/ui/ishara_icon_data.dart';

/// A prototype icon (`data-ic`), drawn in the current text / icon colour.
///
/// Icons that point "forward" (`arrow`, `back`, `chev`) are mirrored in RTL,
/// as the prototype does with `scaleX(-1)`. Decorative by default; pass
/// [semanticLabel] when the icon is the only label of a control.
class IsharaIcon extends StatelessWidget {
  const new(
    this.name, {
    super.key,
    this.size = 20,
    this.color,
    this.semanticLabel,
  });

  /// Icons mirrored in right-to-left layouts.
  static const directional = {'arrow', 'back', 'chev'};

  final String name;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final source = isharaIconSvg[name];
    assert(source != null, 'Unknown prototype icon "$name"');
    final colour =
        color ??
        IconTheme.of(context).color ??
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;
    Widget icon = SvgPicture.string(
      source ?? '',
      width: size,
      height: size,
      theme: SvgTheme(currentColor: colour),
      excludeFromSemantics: true,
    );
    if (directional.contains(name) &&
        Directionality.of(context) == TextDirection.rtl) {
      icon = Transform.flip(flipX: true, child: icon);
    }
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel == null,
      child: icon,
    );
  }
}
