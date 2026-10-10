import 'package:flutter/material.dart';
import 'package:ishara_app/core/router/transitions.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';

/// `#avatar .bubble`: a white speech bubble at the avatar's top start corner
/// (top 14, start 14; 14 px w900; radius 16, 4 at the bottom start), popping
/// in after 0.3 s.
class AvatarBubble extends StatefulWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  State<AvatarBubble> createState() => _AvatarBubbleState();
}

class _AvatarBubbleState extends State<AvatarBubble>
    with SingleTickerProviderStateMixin {
  // popin .5s .3s cubic-bezier(.2,.8,.2,1) both
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final Animation<double> _in = _a.drive(
    CurveTween(curve: const Interval(.3 / .8, 1, curve: IsharaMotion.ease)),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _a.value = 1;
    } else if (!_a.isAnimating && _a.value == 0) {
      _a.forward();
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PositionedDirectional(
    top: 14,
    start: 14,
    end: 14,
    child: Align(
      alignment: AlignmentDirectional.topStart,
      child: PopIn(
        animation: _in,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadiusDirectional.only(
              topStart: Radius.circular(16),
              topEnd: Radius.circular(16),
              bottomEnd: Radius.circular(16),
              bottomStart: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x4028241E),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            widget.text,
            style: DefaultTextStyle.of(context).style.copyWith(
              color: const Color(0xFF0B1026),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    ),
  );
}
