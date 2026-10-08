import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';

/// One tab of [IsharaTabBar].
@immutable
class IsharaTabItem {
  const new({required this.icon, required this.label});

  /// Prototype icon name (`data-ic`).
  final String icon;
  final String label;
}

/// The prototype's bottom tab bar (`.tabbar`, `.tab`, CSS lines 417-420).
class IsharaTabBar extends StatelessWidget {
  const new({
    required this.items,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final List<IsharaTabItem> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.bar,
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, 8, 10, 14 + bottom),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _Tab(
                      item: items[i],
                      on: i == selected,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const new({required this.item, required this.on, required this.onTap});

  final IsharaTabItem item;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // .tab.on: --teal-soft; light theme overrides it to #3446C9 (line 523).
    final colour = on ? (dark ? c.tealSoft : c.teal) : c.muted;
    return Semantics(
      button: true,
      selected: on,
      label: item.label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            if (on)
              Positioned(
                top: -8,
                child: Container(
                  width: 26,
                  height: 3,
                  decoration: BoxDecoration(
                    color: c.teal,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: dark
                        ? [BoxShadow(color: c.teal, blurRadius: 10)]
                        : null,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IsharaIcon(item.icon, size: 23, color: colour),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    style: context.text.tab.copyWith(color: colour),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
