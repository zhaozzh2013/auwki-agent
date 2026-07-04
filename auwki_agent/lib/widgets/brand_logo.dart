import 'package:flutter/material.dart';

import '../theme.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = 28,
    this.showText = true,
    this.color,
  });

  final double size;
  final bool showText;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(size * 0.3),
          ),
          child: CustomPaint(
            painter: _WhalePainter(
              color: Colors.white,
              strokeColor: c,
            ),
          ),
        ),
        if (showText) ...[
          const SizedBox(width: 8),
          Text(
            'AUWKI',
            style: TextStyle(
              color: c,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ],
    );
  }
}

class _WhalePainter extends CustomPainter {
  _WhalePainter({required this.color, required this.strokeColor});

  final Color color;
  final Color strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final body = Path()
      ..moveTo(w * 0.18, h * 0.62)
      ..quadraticBezierTo(w * 0.05, h * 0.55, w * 0.1, h * 0.4)
      ..quadraticBezierTo(w * 0.25, h * 0.18, w * 0.55, h * 0.22)
      ..quadraticBezierTo(w * 0.85, h * 0.28, w * 0.9, h * 0.5)
      ..quadraticBezierTo(w * 0.92, h * 0.7, w * 0.7, h * 0.78)
      ..lineTo(w * 0.28, h * 0.78)
      ..quadraticBezierTo(w * 0.18, h * 0.78, w * 0.18, h * 0.62)
      ..close();
    final bodyPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(body, bodyPaint);

    final eyePaint = Paint()..color = strokeColor;
    canvas.drawCircle(Offset(w * 0.72, h * 0.45), h * 0.055, eyePaint);

    final fin = Path()
      ..moveTo(w * 0.28, h * 0.68)
      ..quadraticBezierTo(w * 0.18, h * 0.92, w * 0.42, h * 0.78)
      ..close();
    canvas.drawPath(fin, bodyPaint);

    final tail = Path()
      ..moveTo(w * 0.16, h * 0.5)
      ..quadraticBezierTo(w * -0.02, h * 0.38, w * 0.05, h * 0.58)
      ..quadraticBezierTo(w * 0.0, h * 0.74, w * 0.16, h * 0.62)
      ..close();
    canvas.drawPath(tail, bodyPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
