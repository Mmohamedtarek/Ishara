import 'package:flutter/material.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';

/// The Ishara mark (prototype `.mark`): a rounded square with the brand
/// gradient and the white logo hand. The same drawing as
/// `brand/ishara_mark.svg`, the source of the app icons (a test keeps them
/// in step).
class IsharaMark extends StatelessWidget {
  /// Splash size (`#splash .mark`: 88 px, radius 26, hand 48).
  const new splash({super.key})
    : size = 88,
      radius = 26,
      hand = 48,
      shadow = const BoxShadow(
        color: Color(0x598E9CFF),
        offset: Offset(0, 20),
        blurRadius: 50,
      );

  /// Header size (`.brand .mark`: 32 px, radius 10, hand 19).
  const new header({super.key})
    : size = 32,
      radius = 10,
      hand = 19,
      shadow = const BoxShadow(
        color: Color(0x598E9CFF),
        offset: Offset(0, 6),
        blurRadius: 18,
      );

  final double size;
  final double radius;
  final double hand;
  final BoxShadow shadow;

  /// linear-gradient(135deg, #4B5BD6, #3446C9 55%, #24309A).
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4B5BD6), Color(0xFF3446C9), Color(0xFF24309A)],
    stops: [0, .55, 1],
  );

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [shadow],
      ),
      alignment: Alignment.center,
      child: IsharaIcon('logo', size: hand, color: Colors.white),
    ),
  );
}
