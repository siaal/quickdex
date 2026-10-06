import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Build with `--dart-define=QUICKDEX_TRACE=true` to route traces to logcat in release.
const bool kTraceToConsole = bool.fromEnvironment('QUICKDEX_TRACE');

/// Developer trace log. `id` is a stable greppable `module.function.branch` string.
void trace(String id, [Map<String, Object?> data = const {}]) {
  final line = '$id ${jsonEncode(data)}';
  if (kTraceToConsole) {
    debugPrint('quickdex $line');
  } else {
    developer.log(line, name: 'quickdex');
  }
}
