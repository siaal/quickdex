import 'package:flutter/material.dart';

const typeColors = <String, Color>{
  'normal': Color(0xFF9FA19F), // Scarlet's grey; the usual olive read as Bug
  'fire': Color(0xFFEE8130),
  'water': Color(0xFF6390F0),
  'electric': Color(0xFFF7D02C),
  'grass': Color(0xFF7AC74C),
  'ice': Color(0xFF96D9D6),
  'fighting': Color(0xFFC22E28),
  'poison': Color(0xFFA33EA1),
  'ground': Color(0xFFE2BF65),
  'flying': Color(0xFFA98FF3),
  'psychic': Color(0xFFF95587),
  'bug': Color(0xFFA6B91A),
  'rock': Color(0xFFB6A136),
  'ghost': Color(0xFF735797),
  'dragon': Color(0xFF6F35FC),
  'dark': Color(0xFF705746),
  'steel': Color(0xFFB7B7CE),
  'fairy': Color(0xFFD685AD),
};

/// Types whose colour is too bright for white text: white contrast below 2.3:1
/// (WCAG relative luminance). Hard-coded from [typeColors] rather than computed
/// at runtime; test/ui/type_style_test.dart checks it still matches the colours.
const darkTextTypes = {'electric', 'ice', 'ground', 'steel', 'grass', 'bug'};

/// Text colour to use on a [typeColors] background.
Color typeTextColor(String t) =>
    darkTextTypes.contains(t) ? Colors.black : Colors.white;

String typeLabel(String t) => t[0].toUpperCase() + t.substring(1);
String typeAbbr(String t) => t.substring(0, 3).toUpperCase();
