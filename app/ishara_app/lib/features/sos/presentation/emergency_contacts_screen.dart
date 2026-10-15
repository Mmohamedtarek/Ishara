import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/list_ui.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/features/sos/application/sos_controller.dart';
import 'package:ishara_app/features/sos/data/emergency_contacts_repository.dart';
import 'package:ishara_app/features/sos/data/sos_platform.dart';
import 'package:ishara_app/features/sos/domain/phone_number.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Settings › Emergency contacts (Q-T4 phase 1): up to 3, typed or picked
/// with the system picker (no contacts permission), stored in E.164 on this
/// phone only.
class EmergencyContactsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final contacts = ref.watch(emergencyContactsProvider).value ?? const [];
    final full = contacts.length >= EmergencyContactsRepository.max;
    return Scaffold(
      key: const ValueKey('screen-emergency'),
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TitleBar(
              leading: IconCircleButton(
                key: const ValueKey('emergency-back'),
                icon: 'back',
                label: l.back,
                onPressed: () => context.pop(),
              ),
              title: l.emergencyContacts,
              lead: l.emergencyLead,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                children: [
                  for (final (i, contact) in contacts.indexed) ...[
                    ActionRow(
                      key: ValueKey('emergency-contact-$i'),
                      icon: 'user',
                      tone: RowTone.amber,
                      title: contact.name,
                      subtitle: contact.phone,
                      chevron: true,
                      onTap: () => unawaited(
                        editContact(context, ref, index: i, current: contact),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (full)
                    Text(
                      l.contactsFull,
                      key: const ValueKey('emergency-full'),
                      style: context.text.rowSubtitle.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.muted,
                      ),
                    ),
                ],
              ),
            ),
            if (!full)
              CtaBar(
                children: [
                  IsharaButton(
                    key: const ValueKey('emergency-add'),
                    label: l.addContact,
                    onPressed: () => unawaited(editContact(context, ref)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Adds ([index] null) or edits a contact in a sheet. After the first
/// contact is added, location while in use is asked for once (with an
/// explanation), so SOS is ready before an emergency.
Future<void> editContact(
  BuildContext context,
  WidgetRef ref, {
  int? index,
  EmergencyContact? current,
}) async {
  final repo = ref.read(emergencyContactsRepositoryProvider);
  final wasEmpty = repo.contacts.isEmpty;
  final result = await showModalBottomSheet<_Edit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.colors.bg2,
    builder: (_) => _ContactSheet(current: current),
  );
  if (result == null) return;
  if (result.remove && index != null) {
    await repo.remove(index);
    return;
  }
  final contact = result.contact!;
  if (index == null) {
    await repo.add(contact);
  } else {
    await repo.replace(index, contact);
  }
  if (wasEmpty && index == null && context.mounted) {
    await askLocationOnce(context, ref);
  }
}

/// Explains, then asks the system for location while in use; with it, the
/// system may offer "Location Accuracy" (this calm moment, never during SOS).
/// Refusing either is fine: SOS works without a location.
Future<void> askLocationOnce(BuildContext context, WidgetRef ref) async {
  final perms = ref.read(locationPermissionsProvider);
  final now = await perms.status();
  if (now == LocationAccess.granted) {
    await perms.offerAccuracy();
    return;
  }
  if (!context.mounted) return;
  final l = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('location-ask'),
      title: Text(l.locationAskTitle),
      content: Text(l.locationAskBody),
      actions: [
        TextButton(
          key: const ValueKey('location-not-now'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.notNow),
        ),
        TextButton(
          key: const ValueKey('location-allow'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.allow),
        ),
      ],
    ),
  );
  if (ok != true) return;
  if (await perms.request() == LocationAccess.granted) {
    await perms.offerAccuracy();
  }
}

class _Edit {
  const new({this.contact, this.remove = false});
  final EmergencyContact? contact;
  final bool remove;
}

class _ContactSheet extends ConsumerStatefulWidget {
  const new({this.current});
  final EmergencyContact? current;

  @override
  ConsumerState<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends ConsumerState<_ContactSheet> {
  late final _name = TextEditingController(text: widget.current?.name);
  late final _phone = TextEditingController(text: widget.current?.phone);
  String? _nameError;
  String? _phoneError;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await ref.read(sosLauncherProvider).pickContact();
    if (picked == null || !mounted) return;
    setState(() {
      if (picked.name.isNotEmpty) _name.text = picked.name;
      _phone.text = picked.number;
    });
  }

  void _save() {
    final l = AppLocalizations.of(context);
    final name = _name.text.trim();
    final phone = PhoneNumber.toE164(_phone.text);
    setState(() {
      _nameError = name.isEmpty ? l.contactNameEmpty : null;
      _phoneError = phone == null ? l.contactPhoneInvalid : null;
    });
    if (name.isEmpty || phone == null) return;
    Navigator.pop(
      context,
      _Edit(
        contact: EmergencyContact(name: name, phone: phone),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    InputDecoration deco(String label, String? error, {String? hint}) =>
        InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: error,
          errorMaxLines: 3,
          filled: true,
          fillColor: c.input,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        18,
        18,
        18 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IsharaLink(
            key: const ValueKey('contact-pick'),
            label: l.pickFromContacts,
            onPressed: _pick,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('contact-name'),
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: deco(l.contactName, _nameError),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('contact-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: deco(
              l.contactPhone,
              _phoneError,
              hint: l.contactPhoneHint,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          IsharaButton(
            key: const ValueKey('contact-save'),
            label: l.saveAction,
            onPressed: _save,
          ),
          if (widget.current != null)
            IsharaLink(
              key: const ValueKey('contact-remove'),
              label: l.removeContact,
              onPressed: () =>
                  Navigator.pop(context, const _Edit(remove: true)),
            ),
        ],
      ),
    );
  }
}
