import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Decides which [AvatarSlot] shows the avatar, like the prototype's
/// `mountAvatar(slot)`: the slot that became visible last wins; when it
/// goes away, the one before it (if still visible) gets the avatar back.
class AvatarSlotRegistry extends ChangeNotifier {
  final List<Object> _claims = [];
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// The one key the avatar view is built under: only one slot (or the
  /// parking spot) builds it per frame, so the native view moves instead of
  /// being recreated.
  final GlobalKey viewKey = GlobalKey(debugLabel: 'avatar view');

  Object? _owner;

  /// The slot showing the avatar, or null (the view is parked offstage).
  /// It changes only when listeners are notified, so every builder of the
  /// view sees the same owner in a frame (one global key, one place).
  Object? get owner => _owner;

  Object? get _wanted => _claims.isEmpty ? null : _claims.last;

  /// [slot] is visible ([active]) or not.
  void update(Object slot, {required bool active}) {
    _claims.remove(slot);
    if (active) _claims.add(slot);
    if (_wanted != _owner) _schedule();
  }

  void release(Object slot) => update(slot, active: false);

  // Slots change during build (route or ticker changes); listeners rebuild
  // after the frame, all in the same frame, so the view's key moves cleanly.
  void _schedule() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _notifyScheduled = false;
        if (_disposed || _wanted == _owner) return;
        _owner = _wanted;
        notifyListeners();
      })
      ..scheduleFrame();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A place on a screen where the avatar can appear (prototype
/// `.avatar-slot`). It shows the avatar while its screen is on stage (the
/// slot that came on stage last wins); otherwise it stays empty.
class AvatarSlot extends StatefulWidget {
  const new({required this.registry, required this.view, super.key});

  final AvatarSlotRegistry registry;

  /// Builds the avatar view (the shared WebView).
  final Widget Function() view;

  @override
  State<AvatarSlot> createState() => _AvatarSlotState();
}

class _AvatarSlotState extends State<AvatarSlot> {
  @override
  void initState() {
    super.initState();
    widget.registry.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Visible = its route is on stage (screens covered by an opaque route
    // and hidden tabs have their tickers off) and not on its way out. A
    // dialog or sheet on top keeps the avatar where it is.
    final visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isActive ?? true);
    widget.registry.update(this, active: visible);
  }

  @override
  void didUpdateWidget(AvatarSlot old) {
    super.didUpdateWidget(old);
    if (old.registry != widget.registry) {
      old.registry
        ..removeListener(_changed)
        ..release(this);
      widget.registry.addListener(_changed);
      didChangeDependencies();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.registry
      ..removeListener(_changed)
      ..release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.registry.owner != this) return const SizedBox.expand();
    return KeyedSubtree(key: widget.registry.viewKey, child: widget.view());
  }
}

/// Keeps the avatar view alive (offstage) while no slot shows it, and
/// pauses rendering then. Sits once at the app root.
class AvatarParking extends StatefulWidget {
  const new({
    required this.registry,
    required this.view,
    required this.onVisible,
    super.key,
  });

  final AvatarSlotRegistry registry;
  final Widget Function() view;

  /// Called with true when a slot shows the avatar, false when none does.
  final ValueChanged<bool> onVisible;

  @override
  State<AvatarParking> createState() => _AvatarParkingState();
}

class _AvatarParkingState extends State<AvatarParking> {
  bool? _visible;

  @override
  void initState() {
    super.initState();
    widget.registry.addListener(_changed);
    _report();
  }

  @override
  void didUpdateWidget(AvatarParking old) {
    super.didUpdateWidget(old);
    if (old.registry != widget.registry) {
      old.registry.removeListener(_changed);
      widget.registry.addListener(_changed);
      _report();
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _report();
  }

  void _report() {
    final v = widget.registry.owner != null;
    if (v == _visible) return;
    _visible = v;
    widget.onVisible(v);
  }

  @override
  void dispose() {
    widget.registry.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.registry.owner != null) return const SizedBox.shrink();
    return Offstage(
      child: SizedBox(
        width: 320,
        height: 300,
        child: KeyedSubtree(key: widget.registry.viewKey, child: widget.view()),
      ),
    );
  }
}
