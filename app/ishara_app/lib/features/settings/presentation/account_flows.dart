import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/account/account_providers.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/sync/sync_providers.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// The app's own root navigator, for dialogs (the outermost navigator is
/// not the app's in golden tests, where several apps share one image).
BuildContext _dialogs(BuildContext context, WidgetRef ref) {
  final nav = ref
      .read(appRouterProvider)
      .routerDelegate
      .navigatorKey
      .currentState;
  return nav?.overlay?.context ?? context;
}

/// A dialog with a spinner while a call runs, and [label] beside it
/// (deleting: N18).
Future<T> _withSpinner<T>(
  BuildContext context,
  Future<T> work, {
  String? label,
}) async {
  unawaited(
    showDialog<void>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: label == null
            ? const Center(child: CircularProgressIndicator())
            : AlertDialog(
                key: const ValueKey('deleting'),
                content: Row(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Semantics(liveRegion: true, child: Text(label)),
                    ),
                  ],
                ),
              ),
      ),
    ),
  );
  try {
    return await work;
  } finally {
    if (context.mounted) Navigator.of(context).pop();
  }
}

/// Settings › Sign out (S10-6).
/// - A guest: just signs out (nothing of theirs is in an account).
/// - Email not verified: nothing reached the account (Q-B3), so the data
///   stays on the phone as guest data; a dialog says so first (N26).
/// - Verified: what's waiting is pushed first; if some can't go, the user
///   decides; then the account's phrases and Learn progress leave the
///   phone (settings, Talk, contacts and the glove stay).
Future<void> signOutFlow(BuildContext screen, WidgetRef ref) async {
  final context = _dialogs(screen, ref);
  final l = AppLocalizations.of(context);
  final user = ref.read(authRepositoryProvider).currentUser;
  final engine = ref.read(syncControlProvider);
  final syncing = user != null && user.emailVerified && engine != null;
  Future<bool> ask(String key, String title, String body) async =>
      await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          key: ValueKey(key),
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              key: const ValueKey('sign-out-cancel'),
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancelAction),
            ),
            TextButton(
              key: const ValueKey('sign-out-anyway'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.sLogout),
            ),
          ],
        ),
      ) ??
      false;
  if (user != null && !user.emailVerified) {
    final go = await ask(
      'sign-out-unverified',
      l.sLogout,
      l.signOutUnverifiedBody,
    );
    if (!go || !context.mounted) return;
  } else if (syncing) {
    final allSent = await _withSpinner(context, engine.flush());
    if (!context.mounted) return;
    if (!allSent &&
        !await ask(
          'sign-out-unsynced',
          l.signOutUnsyncedTitle,
          l.signOutUnsyncedBody,
        )) {
      return;
    }
  }
  await ref.read(authRepositoryProvider).signOut();
  if (syncing) await engine.clearSyncedData();
  if (!context.mounted) return;
  showToast(context, l.toastLogout);
  context.go(AppRoutes.welcome);
}

/// Settings › Delete account (Q-B1): confirm with the account's email,
/// then delete.
Future<void> deleteAccountFlow(BuildContext screen, WidgetRef ref) async {
  final context = _dialogs(screen, ref);
  final user = ref.read(authRepositoryProvider).currentUser;
  if (user == null) return;
  final ok = await showDialog<bool>(
    context: context,
    useRootNavigator: false,
    builder: (_) => _DeleteDialog(email: user.email),
  );
  if (ok != true || !context.mounted) return;
  await runDeletion(context, ref, resume: false);
}

/// Asks for the password and runs [go] with it until it is accepted; null
/// when the user cancels. A refused password shows why and asks again.
Future<DeletionState?> _withPassword(
  BuildContext context,
  Future<DeletionState> Function(String password) go,
) async {
  final l = AppLocalizations.of(context);
  while (context.mounted) {
    final password = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => const _PasswordDialog(),
    );
    if (password == null || !context.mounted) return null;
    try {
      return await _withSpinner(context, go(password), label: l.deleting);
    } on AuthFailure catch (f) {
      if (context.mounted) {
        showToast(
          context,
          f.problem == AuthProblem.invalidCredentials
              ? l.authErrInvalid
              : f.problem == AuthProblem.network
              ? l.authErrNetwork
              : l.authErrUnknown,
        );
      }
    }
  }
  return null;
}

/// Runs (or [resume]s) the deletion with its dialogs: the password first
/// (a new deletion, every time: Q-B1, user 2026-11-27; a cancel deletes
/// nothing), a spinner, the password again only if a resumed deletion
/// needs a recent sign-in, the end state.
Future<void> runDeletion(
  BuildContext screen,
  WidgetRef ref, {
  required bool resume,
}) async {
  final context = _dialogs(screen, ref);
  final l = AppLocalizations.of(context);
  final ctl = ref.read(accountDeletionControllerProvider.notifier);
  final first = resume
      ? await _withSpinner(context, ctl.resume(), label: l.deleting)
      : await _withPassword(context, ctl.start);
  if (first == null) return; // cancelled: nothing was deleted
  var state = first;
  while (state == DeletionState.needsPassword) {
    if (!context.mounted) return;
    final next = await _withPassword(context, ctl.withPassword);
    if (next == null) break;
    state = next;
  }
  if (!context.mounted) return;
  switch (state) {
    case DeletionState.done:
      ctl.acknowledge();
      showToast(context, l.toastDeleted);
      context.go(AppRoutes.welcome);
    case DeletionState.failed:
      ctl.acknowledge();
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          key: const ValueKey('delete-failed'),
          content: Text(l.deleteFailed),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).okButtonLabel),
            ),
          ],
        ),
      );
    case DeletionState.needsPassword ||
        DeletionState.idle ||
        DeletionState.deleting:
      break;
  }
}

class _DeleteDialog extends StatefulWidget {
  const new({required this.email});

  final String email;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _typed = TextEditingController();

  bool get _matches =>
      _typed.text.trim().toLowerCase() == widget.email.trim().toLowerCase();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('delete-confirm'),
      title: Text(l.deleteTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.deleteBody(widget.email)),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('delete-email'),
              controller: _typed,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: l.deleteTypeEmail),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('delete-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancelAction),
        ),
        TextButton(
          key: const ValueKey('delete-go'),
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(l.deleteAccount),
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const new();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('delete-password'),
      title: Text(l.deletePasswordTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.deletePasswordBody),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('delete-password-field'),
            controller: _password,
            obscureText: true,
            autocorrect: false,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: l.lblPw),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('delete-password-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancelAction),
        ),
        TextButton(
          key: const ValueKey('delete-password-go'),
          onPressed: _password.text.isEmpty
              ? null
              : () => Navigator.pop(context, _password.text),
          child: Text(l.continueAction),
        ),
      ],
    );
  }
}

/// At start: a deletion an earlier run left pending is finished, with its
/// dialogs (Q-B1: killed or offline halfway). Sits at the app root.
class PendingDeletionResumer extends ConsumerStatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PendingDeletionResumer> createState() =>
      _PendingDeletionResumerState();
}

class _PendingDeletionResumerState
    extends ConsumerState<PendingDeletionResumer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  Future<void> _check() async {
    final pending = await ref.read(accountDeletionProvider).pending();
    if (pending == null || !mounted) return;
    // runDeletion opens its dialogs on the app's navigator
    await runDeletion(context, ref, resume: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
