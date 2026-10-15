import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/features/sos/application/sos_controller.dart';
import 'package:ishara_app/features/sos/application/sos_message.dart';
import 'package:ishara_app/features/sos/data/emergency_contacts_repository.dart';
import 'package:ishara_app/features/sos/domain/sos_location.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Opens the SOS sheet (Talk › SOS, Q-T4 phase 1). D23 is already being
/// spoken; the sheet starts locating at once. Every action is its own tap
/// and opens another app filled in: nothing goes out by itself.
Future<void> showSosSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: context.colors.bg2,
  builder: (_) => const SosSheet(),
);

class SosSheet extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    final s = ref.watch(sosControllerProvider);
    final ctl = ref.read(sosControllerProvider.notifier);
    final locale = Localizations.localeOf(context).languageCode;
    final where = s.location;
    final message = where == null ? null : sosMessage(l, where, locale);
    final status = switch (where) {
      null => l.sosLocating,
      SosLocation(kind: FixKind.fresh, :final fix?) => l.sosLocFresh(
        SosLocator.accuracy(fix),
      ),
      SosLocation(kind: FixKind.lastKnown, :final fix?) => l.sosLocOld(
        SosLocator.ageMinutes(where.age(clock.now())!),
        SosLocator.accuracy(fix),
      ),
      _ => l.sosLocNone,
    };
    final contacts = s.contacts;
    final ambulance = s.ambulance;
    final buttons = <Widget>[
      if (contacts.isNotEmpty) ...[
        IsharaButton(
          key: const ValueKey('sos-sms'),
          label: where?.fix == null && where != null ? l.sosSmsNoLoc : l.sosSms,
          busy: where == null,
          onPressed: message == null ? null : () => unawaited(ctl.sms(message)),
        ),
        if (s.whatsApp)
          IsharaButton(
            key: const ValueKey('sos-whatsapp'),
            label: contacts.length == 1
                ? l.sosWhatsAppTo(contacts.single.name)
                : l.sosWhatsApp,
            kind: IsharaButtonKind.ghost,
            busy: where == null,
            onPressed: message == null
                ? null
                : () => unawaited(_whatsApp(context, ref, message)),
          ),
        for (final (i, contact) in contacts.indexed)
          IsharaButton(
            key: ValueKey('sos-call-$i'),
            label: l.sosCall(contact.name),
            kind: IsharaButtonKind.ghost,
            leading: IsharaIcon('phone', color: c.ink),
            onPressed: () => unawaited(ctl.dial(contact.phone)),
          ),
      ],
      if (ambulance != null)
        IsharaButton(
          key: const ValueKey('sos-ambulance'),
          label: l.sosAmbulance(ambulance),
          kind: IsharaButtonKind.ghost,
          leading: IsharaIcon('phone', color: c.ink),
          onPressed: () => unawaited(ctl.dial(ambulance)),
        ),
      if (contacts.isEmpty)
        IsharaButton(
          key: const ValueKey('sos-add-contact'),
          label: l.sosAddContact,
          kind: IsharaButtonKind.violet,
          onPressed: () {
            Navigator.pop(context);
            unawaited(context.push(AppRoutes.emergencyContacts));
          },
        ),
    ];
    return SingleChildScrollView(
      key: const ValueKey('sos-sheet'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l.sosTitle,
              textAlign: TextAlign.center,
              style: t.h1.copyWith(color: c.danger),
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (where == null) ...[
                  SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: c.tealSoft,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    status,
                    key: const ValueKey('sos-location'),
                    textAlign: TextAlign.center,
                    style: t.rowSubtitle.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: c.sub,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (s.locationOff) ...[
            const SizedBox(height: 4),
            Text(
              l.sosLocOff,
              key: const ValueKey('sos-location-off'),
              textAlign: TextAlign.center,
              style: t.rowSubtitle.copyWith(fontSize: 12.5, color: c.muted),
            ),
          ],
          const SizedBox(height: 16),
          for (final (i, b) in buttons.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            b,
          ],
          if (contacts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l.sosNothingSent,
              textAlign: TextAlign.center,
              style: t.rowSubtitle.copyWith(fontSize: 12, color: c.muted),
            ),
          ],
        ],
      ),
    );
  }

  /// WhatsApp goes to one contact: picked when there are several.
  static Future<void> _whatsApp(
    BuildContext context,
    WidgetRef ref,
    String message,
  ) async {
    final ctl = ref.read(sosControllerProvider.notifier);
    final contacts = ref.read(sosControllerProvider).contacts;
    final to = contacts.length == 1
        ? contacts.single
        : await showDialog<EmergencyContact>(
            context: context,
            builder: (context) => SimpleDialog(
              key: const ValueKey('sos-pick'),
              title: Text(AppLocalizations.of(context).sosSendTo),
              children: [
                for (final (i, c) in contacts.indexed)
                  SimpleDialogOption(
                    key: ValueKey('sos-pick-$i'),
                    onPressed: () => Navigator.pop(context, c),
                    child: Text(c.name),
                  ),
              ],
            ),
          );
    if (to != null) await ctl.whatsApp(to, message);
  }
}
