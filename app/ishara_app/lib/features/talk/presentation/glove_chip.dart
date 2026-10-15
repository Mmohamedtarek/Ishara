import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/blink.dart';
import 'package:ishara_app/features/talk/application/talk_glove_controller.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// `#gloveChip` (`.chip`): the glove's real state (Q-K2: `#BAT`). Connected:
/// green dot, "Glove connected" and the battery %, or "Glove battery low"
/// (amber, `#BAT LOW`), or no % on USB. Reconnecting after a drop (S7-19):
/// D11. Otherwise D10. Tap: Settings when connected, Pair when not (S7-4).
class GloveChip extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    final light = Theme.of(context).brightness == Brightness.light;
    final glove = ref.watch(gloveStatusProvider).value ?? const GloveStatus();
    final reconnecting = ref.watch(
      talkGloveProvider.select((s) => s.reconnecting),
    );
    final connected = glove.phase == GlovePhase.ready;
    final connecting =
        reconnecting ||
        (glove.isConnected && !connected) ||
        glove.phase == GlovePhase.scanning;
    final battery = glove.battery;
    final low = connected && battery?.level == BatteryLevel.low;
    final text = !connected
        ? (connecting ? l.gloveReconnecting : l.gloveOff)
        : low
        ? l.gloveBattLow
        : l.gloveOn;
    final percent = connected && !low && battery?.level == BatteryLevel.ok
        ? battery?.percent
        : null;
    // .chip / .chip.a (amber) / light variants
    final (bg, border, accent) = low
        ? (
            light ? const Color(0x1AF2A33A) : const Color(0x24F2A33A),
            light ? const Color(0x59F2A33A) : const Color(0x66FACD8C),
            c.amberSoft,
          )
        : (
            light ? const Color(0x1A24309A) : const Color(0x296F7CF0),
            light ? const Color(0x4D24309A) : const Color(0x59C9CFFF),
            c.violetSoft,
          );
    final dot = connected
        ? (low ? c.amber : c.ok)
        : connecting
        ? c.amber
        : c.muted;
    return Semantics(
      button: true,
      label: percent == null ? text : '$text $percent%',
      excludeSemantics: true,
      onTap: () => _open(context, connected: connected),
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: border)),
        child: InkWell(
          key: const ValueKey('talk-glove-chip'),
          customBorder: const StadiumBorder(),
          onTap: () => _open(context, connected: connected),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Blink(
                    on: connecting,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dot,
                        boxShadow: connected
                            ? [BoxShadow(color: dot, blurRadius: 10)]
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      text,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.chip.copyWith(color: c.ink),
                    ),
                  ),
                  if (percent != null) ...[
                    const SizedBox(width: 7),
                    Text(
                      '$percent%',
                      style: context.text.chip.copyWith(color: accent),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void _open(BuildContext context, {required bool connected}) {
    if (connected) {
      context.go(AppRoutes.settings);
    } else {
      unawaited(context.push(AppRoutes.pair));
    }
  }
}
