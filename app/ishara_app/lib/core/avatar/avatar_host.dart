import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/avatar_slots.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';

/// Sits once at the app root (`MaterialApp.builder`): starts the avatar,
/// keeps its one WebView alive while no screen shows it (rendering paused),
/// and passes the OS settings and app lifecycle to it.
class AvatarHost extends ConsumerStatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AvatarHost> createState() => _AvatarHostState();
}

class _AvatarHostState extends ConsumerState<AvatarHost> {
  late final AppLifecycleListener _lifecycle;
  bool _slotVisible = false;
  bool _appVisible = true;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => _setApp(visible: false),
      onShow: () => _setApp(visible: true),
    );
  }

  AvatarController? get _controller =>
      ref.read(avatarRuntimeProvider).value?.controller;

  void _setApp({required bool visible}) {
    _appVisible = visible;
    _apply();
  }

  void _apply() {
    final c = _controller;
    if (c == null) return;
    if (_slotVisible && _appVisible) {
      c.resume();
    } else {
      c.pause();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller?.setReduceMotion(on: MediaQuery.disableAnimationsOf(context));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(avatarRuntimeProvider).value;
    ref.listen(avatarRuntimeProvider, (_, next) {
      final c = next.value?.controller;
      if (c == null) return;
      c.setReduceMotion(on: MediaQuery.disableAnimationsOf(context));
      _apply();
    });
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (runtime != null)
          Positioned(
            left: 0,
            top: 0,
            width: 320,
            height: 300,
            child: AvatarParking(
              registry: ref.watch(avatarSlotRegistryProvider),
              view: runtime.surface.buildView,
              onVisible: (v) {
                _slotVisible = v;
                _apply();
              },
            ),
          ),
      ],
    );
  }
}

/// The avatar card (prototype `#avatar`): rounded stage with the theme's
/// gradient, the silhouette placeholder while the 3D avatar loads (or if it
/// can't run), the avatar itself, and [overlay] on top (caption, bubble,
/// controls: added by the screens).
class AvatarStage extends ConsumerWidget {
  const new({this.overlay, this.radius = 24, super.key});

  final Widget? overlay;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final runtime = ref.watch(avatarRuntimeProvider).value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        // #avatar: radial-gradient(120% 90% at 50% 15%, a 0%, b 55%, c 100%)
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -.7),
            radius: 1.2,
            colors: [c.stageA, c.stageB, c.stageC],
            stops: const [0, .55, 1],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // inset 0 -40px 60px rgba(40,36,30,.18)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Color(0x2E28241E), Color(0x0028241E)],
                ),
              ),
            ),
            if (runtime == null)
              const _Placeholder()
            else
              ValueListenableBuilder(
                valueListenable: runtime.controller.status,
                builder: (context, status, _) => AnimatedOpacity(
                  opacity: status == AvatarStatus.ready ? 0 : 1,
                  duration: const Duration(milliseconds: 600),
                  child: const _Placeholder(),
                ),
              ),
            if (runtime != null)
              // Decorative: what the avatar signs is in the caption.
              ExcludeSemantics(
                child: IgnorePointer(
                  child: AvatarSlot(
                    registry: ref.watch(avatarSlotRegistryProvider),
                    view: runtime.surface.buildView,
                  ),
                ),
              ),
            ?overlay,
          ],
        ),
      ),
    );
  }
}

/// `#avatar .ph`: the silhouette, bottom centre, 62 % wide (max 230).
class _Placeholder extends StatelessWidget {
  const new();

  static const _svg = '''
<svg viewBox="0 0 220 240" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="silG" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#9A958A"/>
<stop offset="1" stop-color="#5A554C"/>
</linearGradient></defs>
<path fill="url(#silG)" d="M110 18c-24 0-40 18-40 44 0 20 9 36 24 43v14
c-38 6-66 34-72 70-2 14-2 34-2 51h180c0-17 0-37-2-51-6-36-34-64-72-70v-14
c15-7 24-23 24-43 0-26-16-44-40-44z"/>
</svg>''';

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = (box.maxWidth * .62).clamp(0, 230).toDouble();
      return Align(
        alignment: Alignment.bottomCenter,
        child: SvgPicture.string(_svg, width: w, height: w * 240 / 220),
      );
    },
  );
}
