import 'package:flutter/material.dart';

abstract class AppColors {
  // Status colors
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Transfer states
  static const Color transferActive = Color(0xFF6366F1);
  static const Color transferPaused = Color(0xFFF59E0B);
  static const Color transferComplete = Color(0xFF22C55E);
  static const Color transferFailed = Color(0xFFEF4444);

  // Trust levels
  static const Color trusted = Color(0xFF22C55E);
  static const Color known = Color(0xFF3B82F6);
  static const Color unknown = Color(0xFF9CA3AF);
  static const Color blocked = Color(0xFFEF4444);
}
