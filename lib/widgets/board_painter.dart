// lib/widgets/board_painter.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../theme/app_theme.dart';

class BoardPainter extends CustomPainter {
  final Map<int, List<List<int>>> tokens;
  final int  currentTurn;
  final bool diceRolled;
  final int  playerIndex;

  BoardPainter({
    required this.tokens,
    required this.currentTurn,
    required this.diceRolled,
    required this.playerIndex,
  });

  static const Map<String, double> _arrows = {
    '6,1':0,'6,2':0,'6,3':0,'6,4':0,'6,5':0,
    '5,6':-math.pi/2,'4,6':-math.pi/2,'3,6':-math.pi/2,
    '2,6':-math.pi/2,'1,6':-math.pi/2,'0,6':-math.pi/2,
    '0,7':0,'0,8':math.pi/2,
    '1,8':math.pi/2,'2,8':math.pi/2,'3,8':math.pi/2,
    '4,8':math.pi/2,'5,8':math.pi/2,
    '6,9':0,'6,10':0,'6,11':0,'6,12':0,'6,13':0,'6,14':0,
    '7,14':math.pi/2,
    '8,14':math.pi,'8,13':math.pi,'8,12':math.pi,
    '8,11':math.pi,'8,10':math.pi,'8,9':math.pi,
    '9,8':math.pi/2,'10,8':math.pi/2,'11,8':math.pi/2,
    '12,8':math.pi/2,'13,8':math.pi/2,'14,8':math.pi/2,
    '14,7':math.pi,'14,6':-math.pi/2,
    '13,6':-math.pi/2,'12,6':-math.pi/2,'11,6':-math.pi/2,
    '10,6':-math.pi/2,'9,6':-math.pi/2,
    '8,5':math.pi,'8,4':math.pi,'8,3':math.pi,
    '8,2':math.pi,'8,1':math.pi,'8,0':math.pi,
    '7,0':-math.pi/2,'6,0':0,
  };

  // Inward arrows for 5-cell home columns
  static const List<double> _homeAngles = [
    0, math.pi/2, math.pi, -math.pi/2,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width  / kBoardSize;
    final ch = size.height / kBoardSize;

    final nestSets = [
      for (int i = 0; i < 4; i++)
        {for (final p in kNestPositions[i]) '${p[0]},${p[1]}'},
    ];
    final hpSets = [
      for (int i = 0; i < 4; i++)
        {for (final p in kHousePaths[i]) '${p[0]},${p[1]}'},
    ];
    final trackSet = {for (final p in kTrackPath) '${p[0]},${p[1]}'};
    final startMap = <String, int>{};
    for (int i = 0; i < 4; i++) {
      startMap['${kStartPositions[i][0]},${kStartPositions[i][1]}'] = i;
    }

    // Token map
    final tokMap = <String, List<(int, int)>>{};
    for (final e in tokens.entries) {
      for (int ti = 0; ti < e.value.length; ti++) {
        final k = '${e.value[ti][0]},${e.value[ti][1]}';
        tokMap.putIfAbsent(k, () => []).add((e.key, ti));
      }
    }

    // ── Paint cells ───────────────────────────────────────────────────────────
    for (int r = 0; r < kBoardSize; r++) {
      for (int c = 0; c < kBoardSize; c++) {
        final key  = '$r,$c';
        final rect = Rect.fromLTWH(
            c * cw + 0.3, r * ch + 0.3, cw - 0.6, ch - 0.6);
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(2));
        final cx  = rect.left + rect.width  / 2;
        final cy  = rect.top  + rect.height / 2;

        int? nestOwner, hpOwner;
        for (int i = 0; i < 4; i++) {
          if (nestSets[i].contains(key)) { nestOwner = i; break; }
        }
        if (nestOwner == null) {
          for (int i = 0; i < 4; i++) {
            if (hpSets[i].contains(key)) { hpOwner = i; break; }
          }
        }

        // Skip centre — drawn as large circle after all cells
        final isCentre = key == '${kFinalHome[0]},${kFinalHome[1]}';

        Color bg;
        if (nestOwner != null) {
          bg = AppColors.nests[nestOwner];
        } else if (isCentre) {
          bg = AppColors.boardHome;
        } else if (kSafeSquares.contains(key)) {
          bg = AppColors.boardSafe;
        } else if (hpOwner != null) {
          bg = AppColors.housePaths[hpOwner];
        } else if (startMap.containsKey(key)) {
          bg = AppColors.players[startMap[key]!].withOpacity(0.85);
        } else if (trackSet.contains(key)) {
          bg = AppColors.boardTrack;
        } else {
          final inCross = (r >= 6 && r <= 8) || (c >= 6 && c <= 8);
          // Junction cells: 4 cells adjacent to centre get home column colour
          // 4 corner cells get matching cross background
          // This eliminates ALL dark gaps in the cross area
          if (r == 7 && c == 6) {
            bg = AppColors.housePaths[0]; // Red home col colour
          } else if (r == 6 && c == 7) {
            bg = AppColors.housePaths[1]; // Green home col colour
          } else if (r == 7 && c == 8) {
            bg = AppColors.housePaths[2]; // Yellow home col colour
          } else if (r == 8 && c == 7) {
            bg = AppColors.housePaths[3]; // Blue home col colour
          } else if ((r == 6 || r == 8) && (c == 6 || c == 8)) {
            // Corner cells: paint white/light so no dark gap
            bg = const Color(0xFFDDDDEE);
          } else if (inCross) {
            bg = const Color(0xFF2A2A48);
          } else {
            bg = AppColors.surface;
          }
        }

        canvas.drawRRect(rr, Paint()..color = bg);
        canvas.drawRRect(rr,
            Paint()
              ..color = AppColors.border.withOpacity(0.45)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.4);

        // Decorations (except centre — done later)
        if (!isCentre) {
          if (kSafeSquares.contains(key)) {
            _star(canvas, cx, cy, cw * 0.27, Colors.white70);
          }
          final arrowAngle = _arrows[key];
          if (arrowAngle != null &&
              !kSafeSquares.contains(key) &&
              !startMap.containsKey(key)) {
            _arrow(canvas, cx, cy, cw * 0.32, arrowAngle,
                Colors.white.withOpacity(0.9));
          }
          if (hpOwner != null) {
            _arrow(canvas, cx, cy, cw * 0.28, _homeAngles[hpOwner],
                Colors.white.withOpacity(0.95));
          }
          // Junction cells: draw inward arrow toward centre
          if (r == 7 && c == 6 && !isCentre) {
            _arrow(canvas, cx, cy, cw * 0.28, 0,
                Colors.white.withOpacity(0.95));
          } else if (r == 6 && c == 7 && !isCentre) {
            _arrow(canvas, cx, cy, cw * 0.28, math.pi / 2,
                Colors.white.withOpacity(0.95));
          } else if (r == 7 && c == 8 && !isCentre) {
            _arrow(canvas, cx, cy, cw * 0.28, math.pi,
                Colors.white.withOpacity(0.95));
          } else if (r == 8 && c == 7 && !isCentre) {
            _arrow(canvas, cx, cy, cw * 0.28, -math.pi / 2,
                Colors.white.withOpacity(0.95));
          }
        }

        // Tokens
        final here = tokMap[key];
        if (here != null && here.isNotEmpty && !isCentre) {
          _drawTokens(canvas, rect, here, cw);
        }
      }
    }

    // ── Draw centre home as a circle sized to fit within its own cell ─────────
    // Kept small on purpose so it never bleeds into the 6th house-path cell
    // of any colour's column — those are painted as part of the cell loop
    // above and must stay fully visible.
    final homeCx = 7 * cw + cw / 2;
    final homeCy = 7 * ch + ch / 2;
    final homeR  = cw * 0.42; // safely inside the centre cell, no overlap

    // Outer glow — tight radius/blur so it doesn't spill onto neighbours
    canvas.drawCircle(Offset(homeCx, homeCy), homeR,
        Paint()
          ..color = Colors.purple.withOpacity(0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));

    // Main circle
    canvas.drawCircle(Offset(homeCx, homeCy), homeR,
        Paint()..color = AppColors.boardHome);

    // Multi-coloured wedges (like physical board centre star) — each wedge
    // points toward the side of the hub where that colour's own home column
    // physically sits, not just a fixed clockwise order.
    final wedgePaint = Paint()..style = PaintingStyle.fill;
    const wedgeColors = [
      Color(0xFFE53935), // Red    (column sits west of centre)
      Color(0xFF43A047), // Green  (column sits north of centre)
      Color(0xFFFDD835), // Yellow (column sits east of centre)
      Color(0xFF1E88E5), // Blue   (column sits south of centre)
    ];
    const wedgeCenterAngles = [
      math.pi,        // Red    -> west
      -math.pi / 2,   // Green  -> north
      0.0,            // Yellow -> east
      math.pi / 2,    // Blue   -> south
    ];
    for (int i = 0; i < 4; i++) {
      wedgePaint.color = wedgeColors[i].withOpacity(0.55);
      final startAngle = wedgeCenterAngles[i] - math.pi / 4;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(homeCx, homeCy), radius: homeR * 0.88),
        startAngle, math.pi / 2, true, wedgePaint,
      );
    }

    // White border ring
    canvas.drawCircle(Offset(homeCx, homeCy), homeR,
        Paint()
          ..color = Colors.white.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    // House emoji in centre
    final tp = TextPainter(
      text: const TextSpan(
          text: '🏠',
          style: TextStyle(fontSize: 20, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset(homeCx - tp.width / 2, homeCy - tp.height / 2));

    // Draw tokens ON the centre square on top of circle
    final centreKey = '${kFinalHome[0]},${kFinalHome[1]}';
    final centreRect = Rect.fromLTWH(
        7 * cw + 0.3, 7 * ch + 0.3, cw - 0.6, ch - 0.6);
    final centreTokens = tokMap[centreKey];
    if (centreTokens != null && centreTokens.isNotEmpty) {
      _drawTokens(canvas, centreRect, centreTokens, cw);
    }
  }

  void _drawTokens(Canvas canvas, Rect rect,
      List<(int, int)> toks, double cw) {
    if (toks.length == 1) {
      final (pi, ti) = toks.first;
      final color    = AppColors.players[pi];
      final r        = cw * 0.33;
      final cx = rect.left + rect.width  / 2;
      final cy = rect.top  + rect.height / 2;
      final highlight = diceRolled && pi == playerIndex;
      if (highlight) {
        canvas.drawCircle(Offset(cx, cy), r + 3,
            Paint()
              ..color = color.withOpacity(0.5)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      }
      canvas.drawCircle(Offset(cx + 1, cy + 1.5), r,
          Paint()..color = Colors.black38);
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = color);
      canvas.drawCircle(Offset(cx, cy), r,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      _text(canvas, '${ti + 1}', rect, cw * 0.26,
          color: Colors.white, bold: true);
    } else {
      for (int k = 0; k < math.min(toks.length, 4); k++) {
        final (pi, _) = toks[k];
        final ox = k * cw * 0.13 - toks.length * cw * 0.065;
        final oy = k * cw * 0.09  - toks.length * cw * 0.045;
        final cx = rect.left + rect.width  / 2 + ox;
        final cy = rect.top  + rect.height / 2 + oy;
        canvas.drawCircle(Offset(cx, cy), cw * 0.19,
            Paint()..color = AppColors.players[pi]);
        canvas.drawCircle(Offset(cx, cy), cw * 0.19,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      }
    }
  }

  void _arrow(Canvas canvas, double cx, double cy,
      double r, double angle, Color color) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(-r * 0.5,  r * 0.55)
      ..lineTo(-r * 0.5, -r * 0.55)
      ..close();
    // Dark outline first so the arrow stays readable on any tile colour
    canvas.drawPath(path,
        Paint()
          ..color = Colors.black.withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  void _star(Canvas canvas, double cx, double cy, double r, Color color) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final a  = i * math.pi / 5 - math.pi / 2;
      final rd = i.isEven ? r : r * 0.42;
      final x  = cx + math.cos(a) * rd;
      final y  = cy + math.sin(a) * rd;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _text(Canvas canvas, String t, Rect rect, double fs,
      {Color color = Colors.white, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              fontSize: fs, color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset(rect.left + (rect.width  - tp.width)  / 2,
               rect.top  + (rect.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(BoardPainter old) =>
      old.tokens      != tokens      ||
      old.currentTurn != currentTurn ||
      old.diceRolled  != diceRolled;
}
