import "package:flutter/material.dart";

const _profileColors = <Color>[
  Color(0xFF7C3AED),
  Color(0xFF2563EB),
  Color(0xFF0891B2),
  Color(0xFF059669),
  Color(0xFF65A30D),
  Color(0xFFCA8A04),
  Color(0xFFEA580C),
  Color(0xFFDC2626),
  Color(0xFFDB2777),
  Color(0xFF9333EA),
  Color(0xFF475569),
  Color(0xFF0F766E),
];

Color profileColorFor(String seed) {
  final value = seed.trim().toLowerCase();
  if (value.isEmpty) return _profileColors.first;
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return _profileColors[hash % _profileColors.length];
}

Color profileForegroundFor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : const Color(0xFF111827);
}

class ProfileAvatar extends StatelessWidget {
  final String initials;
  final String seed;
  final double? radius;

  const ProfileAvatar({
    super.key,
    required this.initials,
    required this.seed,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final background = profileColorFor(seed.isEmpty ? initials : seed);
    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      foregroundColor: profileForegroundFor(background),
      child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}
