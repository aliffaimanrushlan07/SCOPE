import 'package:flutter/material.dart';

/// An 8-bit enforcement officer who raises a hand to say "stop".
///
/// Drawn from character maps on a 20-pixel grid so it keeps the pixel-art
/// look of the SCOPE mark at any size. The loop is 3.2 s: the hand goes up
/// and down every 0.8 s, the figure bobs twice as fast, and the eyes blink
/// once near the end. With the system's reduce-motion setting on, the officer
/// holds the raised-hand pose instead of animating.
class PixelOfficer extends StatefulWidget {
  const PixelOfficer({super.key, this.size = 110});

  final double size;

  @override
  State<PixelOfficer> createState() => _PixelOfficerState();
}

class _PixelOfficerState extends State<PixelOfficer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      image: true,
      label: 'Pixel-art enforcement officer raising a hand to signal stop',
      child: AnimatedBuilder(
        animation: _loop,
        builder: (context, _) {
          final ms = _loop.value * 3200;
          return CustomPaint(
            size: Size.square(widget.size),
            painter: _OfficerPainter(
              handUp: still || ms % 1600 >= 800,
              bobbed: !still && ms % 800 >= 400,
              blinking: !still && ms >= 2667,
            ),
          );
        },
      ),
    );
  }
}

class _OfficerPainter extends CustomPainter {
  _OfficerPainter({
    required this.handUp,
    required this.bobbed,
    required this.blinking,
  });

  final bool handUp;
  final bool bobbed;
  final bool blinking;

  static const _palette = {
    'K': Color(0xFF0B2F2C), // outline, belt, shoes
    'C': Color(0xFF115E59), // cap
    'U': Color(0xFF1F7A73), // uniform
    'L': Color(0xFF2DD4BF), // highlight edge, top-left light as in the mark
    'Y': Color(0xFFE8B36A), // cap badge, buckle
    'G': Color(0xFFE8B36A), // chest badge
    'S': Color(0xFFE0A878), // skin
    'D': Color(0xFFC08457), // mouth
    'W': Color(0xFFFFFFFF), // shirt collar
  };

  static const _body = [
    '......KKKKKKKK......',
    '.....KCCCCCCCCK.....',
    '....KCCCCYYCCCCK....',
    '....KCLCCYYCCCCK....',
    '...KKKKKKKKKKKKKK...',
    '....KKSSSSSSSSKK....',
    '.....KSSSSSSSSK.....',
    '.....KSKSSSSKSK.....',
    '.....KSSSSSSSSK.....',
    '.....KSSSDDSSSK.....',
    '......KKSSSSKK......',
    '....KKUUUWWUUUKK....',
    '...KUUUUUWWUUUUUK...',
    '...KULUGUUUUUUUUK...',
    '...KULUUUUUUUUUUK...',
    '...KUUUUUUUUUUUUK...',
    '...KKKKKKYYKKKKKK...',
    '....KUUUUKKUUUUK....',
    '....KUUUUKKUUUUK....',
    '....KUUUUKKUUUUK....',
    '...KKKKKKKKKKKKKK...',
  ];

  /// Sprites placed at a column offset, keyed by their first row.
  static const _leftArm = (0, 12, ['KUU', 'KUU', 'KUU', 'KUU', 'KSS', 'KKK']);
  static const _armDown = (17, 12, ['UUK', 'UUK', 'UUK', 'UUK', 'SSK', 'KKK']);
  static const _armUp = (
    16,
    0,
    [
      'KKKK', 'KSSK', 'KSSK', 'KSSK', 'KUUK', 'KUUK', 'KUUK', //
      'KUUK', 'KUUK', 'KUUK', 'KUUK', 'KUUK', '.UUK', '.KKK',
    ],
  );
  static const _lids = [(7, 7), (12, 7)];

  @override
  void paint(Canvas canvas, Size size) {
    // 20 columns plus one pixel of margin each side, so the raised hand and
    // the bob never touch the edge.
    final px = size.width / 22;
    final paint = Paint()..isAntiAlias = false;

    canvas.save();
    canvas.translate(px, px - (bobbed ? px * 0.4 : 0));

    void dot(int x, int y, Color color) {
      paint.color = color;
      // A hair of overlap hides seams between neighbouring squares.
      canvas.drawRect(Rect.fromLTWH(x * px, y * px, px + 0.5, px + 0.5), paint);
    }

    void sprite((int, int, List<String>) s) {
      final (x0, y0, rows) = s;
      for (var y = 0; y < rows.length; y++) {
        for (var x = 0; x < rows[y].length; x++) {
          final color = _palette[rows[y][x]];
          if (color != null) dot(x0 + x, y0 + y, color);
        }
      }
    }

    sprite((0, 0, _body));
    sprite(_leftArm);
    sprite(handUp ? _armUp : _armDown);
    if (blinking) {
      for (final (x, y) in _lids) {
        dot(x, y, _palette['S']!);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OfficerPainter old) =>
      old.handUp != handUp || old.bobbed != bobbed || old.blinking != blinking;
}
