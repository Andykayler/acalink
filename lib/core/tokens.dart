import 'package:flutter/material.dart';

/// Non-color helpers shared across ACALink screens. The color palette itself
/// used to live here as `class T` — superseded by the theme-aware
/// [AppColors] extension in `theme/app_colors.dart` (`context.colors`), so
/// both light and dark actually work instead of this being a single static
/// light-only palette.
///
/// Deterministic avatar tint, so the same person keeps the same colour
/// everywhere in the app. Mirrors the web portal's `tintFor`.
const _avatarTints = <Color>[
  Color(0xFF4F6EF7),
  Color(0xFF8B5CF6),
  Color(0xFF0EA5E9),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFFEC4899),
  Color(0xFF14B8A6),
];

Color tintFor(String id) {
  var sum = 0;
  for (final unit in id.codeUnits) {
    sum += unit;
  }
  return _avatarTints[sum % _avatarTints.length];
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

String relativeTime(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.day}/${dt.month}/${dt.year}';
}
