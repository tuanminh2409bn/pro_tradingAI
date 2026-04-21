import 'package:flutter/material.dart';

class AppColors {
  // Main Theme Colors
  static const Color background = Color(0xFF101010); // Dark Background
  static const Color surface = Color(0xFF1A1A1A);    // Surface Color
  static const Color primary = Color(0xFF00FF7F);   // Spring Green (Solid Boxes)
  static const Color secondary = Color(0xFFBA55D3); // Pale Orchid (Labels)
  static const Color accent = Color(0xFFFFD700);    // Gold (Dashed Lines / Highlights)
  
  // Trading Colors
  static const Color bull = Color(0xFF00FF7F);      // Green
  static const Color bear = Color(0xFFFF4500);      // Orange Red (Solid Boxes)
  static const Color neutral = Color(0xFFA9A9A9);   // Dark Gray (Candle Overrides)
  
  // Alert & Specialized Colors
  static const Color alert = Color(0xFFFF0000);     // Red ($$$ Tag / SL)
  static const Color entry = Color(0xFF0000FF);     // Blue (Entry Lines)
  static const Color tp = Color(0xFF00FF00);        // Pure Green (TP Lines)
  static const Color ghostOverlay = Color(0x26FFFFFF); // 15% Opacity White
  static const Color redZone = Color(0x4DFF0000);   // Transparent Red Zone
  
  // Border Colors
  static const Color border = Color(0xFFF0E68C);    // Khaki (Bordered Boxes)
}
