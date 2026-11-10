import 'package:flutter/material.dart';

/// The Stash mark: a small pile of saved videos on the brand indigo.
///
/// The same painter draws the in-app mark and the launcher icons
/// (see test_screens/icon_test.dart), so the two never drift apart.
class StashLogo extends StatelessWidget {
  const StashLogo({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Stash',
    image: true,
    child: CustomPaint(size: Size.square(size), painter: const StashLogoPainter()),
  );
}

class StashLogoPainter extends CustomPainter {
  const StashLogoPainter({this.background = true, this.cornerRadius = 0.26, this.glyphScale = 1});

  /// Draw the indigo tile behind the glyph.
  final bool background;

  /// Corner radius of the tile as a fraction of its side; 0 for a full square.
  final double cornerRadius;

  /// Shrinks the glyph, e.g. to fit an adaptive icon's safe zone.
  final double glyphScale;

  static const top = Color(0xFF7676F2);
  static const bottom = Color(0xFF4B45C6);
  static const ink = Color(0xFF5B5BD6);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (background) {
      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ).createShader(rect);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(size.shortestSide * cornerRadius)), paint);
    }

    final w = size.shortestSide * glyphScale;
    final c = rect.center;

    void card(double angle, Offset shift, double opacity) {
      canvas.save();
      canvas.translate(c.dx + shift.dx * w, c.dy + shift.dy * w);
      canvas.rotate(angle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w * 0.40, height: w * 0.52),
          Radius.circular(w * 0.085),
        ),
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
      canvas.restore();
    }

    card(-0.38, const Offset(-0.09, -0.005), 0.38);
    card(-0.17, const Offset(-0.02, -0.02), 0.66);
    card(0.06, const Offset(0.075, 0.01), 1);

    // Play triangle on the front card, optically centred.
    canvas.save();
    canvas.translate(c.dx + 0.075 * w, c.dy + 0.01 * w);
    canvas.rotate(0.06);
    final r = w * 0.085;
    final tri = Path()
      ..moveTo(-r * 0.72, -r)
      ..lineTo(r * 1.05, 0)
      ..lineTo(-r * 0.72, r)
      ..close();
    final paint = Paint()
      ..color = ink
      ..style = PaintingStyle.fill;
    canvas.drawPath(tri, paint);
    canvas.drawPath(
      tri,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.03
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(StashLogoPainter old) =>
      old.background != background || old.cornerRadius != cornerRadius || old.glyphScale != glyphScale;
}
