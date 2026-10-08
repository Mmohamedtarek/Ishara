import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/router/transitions.dart';
import 'package:ishara_app/core/ui/ishara_tab_bar.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// The 4 tabs (Talk, Learn, History, Settings) with the prototype tab bar.
/// Switching tabs replays the screen entrance, as `show()` does in the
/// prototype, and resets the stack of the chosen tab (`tab()`).
class TabShell extends StatefulWidget {
  const new({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  State<TabShell> createState() => _TabShellState();
}

class _TabShellState extends State<TabShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
  );

  @override
  void didUpdateWidget(TabShell old) {
    super.didUpdateWidget(old);
    if (old.shell.currentIndex != widget.shell.currentIndex) {
      _entrance.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: ScreenEntranceTransition(animation: _entrance, child: widget.shell),
      bottomNavigationBar: IsharaTabBar(
        selected: widget.shell.currentIndex,
        onSelect: (i) => widget.shell.goBranch(i, initialLocation: true),
        items: [
          IsharaTabItem(icon: 'chat', label: l.tabTalk),
          IsharaTabItem(icon: 'book', label: l.tabLearn),
          IsharaTabItem(icon: 'clock', label: l.tabHistory),
          IsharaTabItem(icon: 'gear', label: l.tabSettings),
        ],
      ),
    );
  }
}
