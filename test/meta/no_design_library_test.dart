import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `lib/` must stay design-library agnostic: importing either the in-SDK
/// `material.dart` / `cupertino.dart` (deprecated since Flutter 3.50) or the
/// standalone `material_ui` / `cupertino_ui` packages would either break on a
/// future SDK or drop every Flutter release older than those packages.
void main() {
  test('lib/ imports no design library', () {
    final forbidden = RegExp(
      r'''^\s*(import|export)\s+['"]package:(flutter/(material|cupertino)\.dart|material_ui/|cupertino_ui/)''',
      multiLine: true,
    );
    final offenders = <String>[
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') && forbidden.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(offenders, isEmpty, reason: 'Use package:flutter/widgets.dart instead.');
  });
}
