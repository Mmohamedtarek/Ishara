import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/storage/storage_health.dart';
import 'package:ishara_app/core/storage/storage_providers.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Step 10a review: the first change this session that can't be saved
/// shows "out of storage" once (draft N1), in the toast's look, for
/// [shown], and screen readers announce it. It never takes a tap, so it
/// blocks nothing (SOS above all). Sits at the app root (`IsharaApp`).
class StorageNotice extends ConsumerStatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  /// Longer than a toast: two sentences.
  static const shown = Duration(seconds: 6);

  @override
  ConsumerState<StorageNotice> createState() => _StorageNoticeState();
}

class _StorageNoticeState extends ConsumerState<StorageNotice> {
  final ValueNotifier<bool> _visible = ValueNotifier(false);
  bool _done = false;
  Timer? _timer;
  late final StorageHealth _health;

  @override
  void initState() {
    super.initState();
    _health = ref.read(storageHealthProvider)..notSaving.addListener(_check);
    // a write may have failed before the first frame (the migration)
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_done || !mounted) return;
    if (!_health.notSaving.value) return;
    _done = true; // once per session
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _visible.value = true;
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          AppLocalizations.of(context).storageFull,
          Directionality.of(context),
        ),
      );
    });
    _timer = Timer(StorageNotice.shown, () {
      if (mounted) _visible.value = false;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _health.notSaving.removeListener(_check);
    _visible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      if (_done)
        ToastView(
          key: const ValueKey('storage-notice'),
          message: AppLocalizations.of(context).storageFull,
          visible: _visible,
        ),
    ],
  );
}
