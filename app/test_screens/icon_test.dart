// Regenerates every launcher icon from the logo painter in lib/ui/logo.dart:
//
//   flutter test test_screens/icon_test.dart
//
// Writes the Android mipmaps (legacy + adaptive foreground), the iOS
// AppIcon set and a preview at ../screenshots/icon.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stash/ui/logo.dart';

Future<void> _write(String path, int px, StashLogoPainter painter, {Color? matte}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final size = Size.square(px.toDouble());
  if (matte != null) canvas.drawRect(Offset.zero & size, Paint()..color = matte);
  painter.paint(canvas, size);
  final image = await rec.endRecording().toImage(px, px);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path)..createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('write launcher icons', (tester) async {
    await tester.runAsync(() async {
      const res = 'android/app/src/main/res';
      const densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
      for (final e in densities.entries) {
        // Legacy icon: the rounded tile itself.
        await _write('$res/mipmap-${e.key}/ic_launcher.png', (48 * e.value).round(), const StashLogoPainter());
        // Adaptive foreground: glyph only, inside the 66dp safe zone of 108dp.
        await _write(
          '$res/mipmap-${e.key}/ic_launcher_foreground.png',
          (108 * e.value).round(),
          const StashLogoPainter(background: false, glyphScale: 0.62),
        );
      }

      // iOS wants full-bleed squares; the system applies the mask.
      const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      const sizes = {
        'Icon-App-20x20@1x': 20,
        'Icon-App-20x20@2x': 40,
        'Icon-App-20x20@3x': 60,
        'Icon-App-29x29@1x': 29,
        'Icon-App-29x29@2x': 58,
        'Icon-App-29x29@3x': 87,
        'Icon-App-40x40@1x': 40,
        'Icon-App-40x40@2x': 80,
        'Icon-App-40x40@3x': 120,
        'Icon-App-60x60@2x': 120,
        'Icon-App-60x60@3x': 180,
        'Icon-App-76x76@1x': 76,
        'Icon-App-76x76@2x': 152,
        'Icon-App-83.5x83.5@2x': 167,
        'Icon-App-1024x1024@1x': 1024,
      };
      for (final e in sizes.entries) {
        await _write(
          '$ios/${e.key}.png',
          e.value,
          const StashLogoPainter(cornerRadius: 0),
          matte: StashLogoPainter.bottom,
        );
      }

      await _write('../screenshots/icon.png', 512, const StashLogoPainter());
      await _write('../screenshots/icon_small.png', 96, const StashLogoPainter());
    });
  });
}
