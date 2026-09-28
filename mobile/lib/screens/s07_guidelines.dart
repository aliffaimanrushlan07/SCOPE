import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../widgets/pixel_officer.dart';

/// S07 — Reporting Guidelines.
///
/// A five-card swipe deck, one idea per card: safety, what counts, photo
/// evidence, privacy, and what happens after submission. Each card says its
/// rule in a line or two and lets icons and pictures carry the rest.
///
/// The safety card is first on purpose, and the only dark one. The reporter
/// may be standing next to the person they are reporting, and "do not
/// confront" is the single most important thing this screen says.
///
/// Skip jumps to the last card rather than closing the screen: "keep your
/// reference number" is the one thing a skipping reader still needs.
class GuidelinesScreen extends StatefulWidget {
  const GuidelinesScreen({super.key});

  @override
  State<GuidelinesScreen> createState() => _GuidelinesScreenState();
}

class _GuidelinesScreenState extends State<GuidelinesScreen> {
  static const _cards = <Widget>[
    _SafetyCard(),
    _WhatCountsCard(),
    _PhotoCard(),
    _PrivacyCard(),
    _AfterSubmitCard(),
  ];
  static const _motion = Duration(milliseconds: 280);

  final _pages = PageController();
  int _page = 0;

  bool get _dark => _page == 0;
  bool get _last => _page == _cards.length - 1;

  void _goTo(int page) =>
      _pages.animateToPage(page, duration: _motion, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fg = _dark ? Colors.white : ScopeTheme.ink;
    final accent = _dark ? ScopeTheme.teal200 : ScopeTheme.primary;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: AnimatedContainer(
          duration: _motion,
          color: _dark ? ScopeTheme.glass : Colors.white,
          child: SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      BackButton(color: fg),
                      Expanded(
                        child: Text(
                          'Reporting Guidelines',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                      ),
                      if (!_last)
                        TextButton(
                          onPressed: () => _goTo(_cards.length - 1),
                          style: TextButton.styleFrom(foregroundColor: accent),
                          child: const Text(
                            'Skip',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      const SizedBox(width: Gap.sm),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (page) => setState(() => _page = page),
                    children: _cards,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.lg,
                    Gap.md,
                    Gap.lg,
                    Gap.lg,
                  ),
                  child: Column(
                    children: [
                      _Dots(count: _cards.length, index: _page, dark: _dark),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          if (_page > 0) ...[
                            SizedBox(
                              width: 52,
                              child: OutlinedButton(
                                onPressed: () => _goTo(_page - 1),
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                ),
                                child: const Icon(
                                  Icons.chevron_left,
                                  size: 28,
                                  semanticLabel: 'Previous',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: FilledButton(
                              onPressed: _last
                                  ? () => Navigator.of(context).maybePop()
                                  : () => _goTo(_page + 1),
                              style: _dark
                                  ? FilledButton.styleFrom(
                                      backgroundColor: ScopeTheme.teal200,
                                      foregroundColor: ScopeTheme.glass,
                                    )
                                  : null,
                              child: Text(_last ? 'Got it' : 'Next'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index, required this.dark});

  final int count;
  final int index;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Card ${index + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 22 : 8,
              height: 8,
              color: i == index
                  ? (dark ? ScopeTheme.teal200 : ScopeTheme.primary)
                  : (dark ? const Color(0xFF2C5C58) : ScopeTheme.teal100),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

/// Scrolls on short phones; on most screens the card fits without it.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 20),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Square uppercase label, the design system's pixel-surface tag.
class _Tag extends StatelessWidget {
  const _Tag(
    this.text, {
    this.fg = ScopeTheme.primary,
    this.bg = ScopeTheme.teal100,
  });

  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: bg,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: fg,
          ),
        ),
      ),
    );
  }
}

const _headingStyle = TextStyle(
  fontSize: 30,
  height: 36 / 30,
  fontWeight: FontWeight.w800,
  color: ScopeTheme.ink,
);

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.color = ScopeTheme.ink});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: _headingStyle.copyWith(color: color)),
  );
}

class _Lead extends StatelessWidget {
  const _Lead(this.text, {this.color = ScopeTheme.inkMuted, this.size = 16});

  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: size, height: 24 / size, color: color),
  );
}

/// Icon plus one line of text in a rounded panel.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.leading,
    required this.text,
    this.filled = true,
  });

  final Widget leading;
  final InlineSpan text;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: filled ? ScopeTheme.tint : null,
        border: filled ? null : Border.all(color: ScopeTheme.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              text,
              style: const TextStyle(
                fontSize: 15,
                height: 20 / 15,
                color: ScopeTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _bold = TextStyle(fontWeight: FontWeight.w700);

/// Lays [children] out two per row, each row as tall as its tallest tile.
class _TwoUp extends StatelessWidget {
  const _TwoUp({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 2) ...[
          if (i > 0) const SizedBox(height: Gap.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 1 · Safety
// ---------------------------------------------------------------------------

class _SafetyCard extends StatelessWidget {
  const _SafetyCard();

  static const _rules = [
    (Icons.comments_disabled_outlined, 'Don’t confront or argue'),
    (Icons.visibility_outlined, 'Don’t draw attention to yourself'),
    (Icons.directions_walk, 'Feel unsafe? Just leave'),
  ];

  @override
  Widget build(BuildContext context) {
    return _Card(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 132,
            height: 132,
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1B4F4B),
              border: Border.all(color: ScopeTheme.teal200, width: 2),
            ),
            child: const PixelOfficer(size: 110),
          ),
        ),
        const _Tag('Rule no. 1', fg: ScopeTheme.glass, bg: ScopeTheme.teal200),
        const _Heading('Your safety comes first', color: Colors.white),
        const _Lead(
          'No report is worth your safety. SCOPE exists so you never have '
          'to step in.',
          color: Color(0xFFCFE9E5),
          size: 17,
        ),
        Column(
          children: [
            for (final (icon, text) in _rules)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF164541),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: ScopeTheme.teal200),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        text,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 2 · What counts
// ---------------------------------------------------------------------------

class _WhatCountsCard extends StatelessWidget {
  const _WhatCountsCard();

  static const _premises = [
    (Icons.restaurant_outlined, 'Restaurants & cafés'),
    (Icons.ac_unit, 'Air-conditioned premises'),
    (Icons.local_mall_outlined, 'Shopping malls'),
    (Icons.local_hospital_outlined, 'Hospitals & clinics'),
    (Icons.school_outlined, 'Schools & colleges'),
    (Icons.directions_bus_outlined, 'Transport hubs'),
  ];

  @override
  Widget build(BuildContext context) {
    return _Card(
      children: [
        const _Tag('What counts'),
        Semantics(
          header: true,
          child: Text.rich(
            const TextSpan(
              children: [
                TextSpan(text: 'A '),
                TextSpan(
                  text: 'lit',
                  style: TextStyle(color: ScopeTheme.violation),
                ),
                TextSpan(text: ' cigarette in a no‑smoking place'),
              ],
            ),
            style: _headingStyle,
          ),
        ),
        _TwoUp(
          children: [
            for (final (icon, label) in _premises)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ScopeTheme.tint,
                  border: Border.all(color: ScopeTheme.teal100),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: ScopeTheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 18 / 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const Text(
          'NOT A VIOLATION UNDER ACT 852',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: ScopeTheme.inkMuted,
          ),
        ),
        const _TwoUp(
          children: [_NotAllowed('Unlit cigarette'), _NotAllowed('Vape')],
        ),
      ],
    );
  }
}

class _NotAllowed extends StatelessWidget {
  const _NotAllowed(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        border: Border.all(color: const Color(0xFFF3C2C2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.close, color: ScopeTheme.violation, size: 20),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3 · Photo evidence
// ---------------------------------------------------------------------------

enum _Shot { good, far, blurry }

class _PhotoCard extends StatelessWidget {
  const _PhotoCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      children: [
        const _Tag('Photo evidence'),
        const _Heading('Show the ember'),
        const _Lead('The lit end must be clear in the frame.'),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _ShotExample(_Shot.good, 'Lit end in view')),
            SizedBox(width: 10),
            Expanded(child: _ShotExample(_Shot.far, 'Too far away')),
            SizedBox(width: 10),
            Expanded(child: _ShotExample(_Shot.blurry, 'Blurry')),
          ],
        ),
        Column(
          children: [
            _InfoRow(
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 14,
                      height: 18,
                      margin: const EdgeInsets.only(right: 4),
                      color: ScopeTheme.primary,
                    ),
                ],
              ),
              text: const TextSpan(
                children: [
                  TextSpan(text: 'Up to 3 photos.', style: _bold),
                  TextSpan(text: ' Only ones that pass the check are kept.'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const _InfoRow(
              leading: Icon(
                Icons.shield_outlined,
                color: ScopeTheme.primary,
                size: 22,
              ),
              text: TextSpan(
                children: [
                  TextSpan(text: 'Close enough to see, '),
                  TextSpan(
                    text: 'never close enough to be at risk.',
                    style: _bold,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ShotExample extends StatelessWidget {
  const _ShotExample(this.shot, this.caption);

  final _Shot shot;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final ok = shot == _Shot.good;
    final color = ok ? ScopeTheme.primary : ScopeTheme.violation;
    Widget scene = CustomPaint(
      size: const Size.fromHeight(96),
      painter: _ScenePainter(far: shot == _Shot.far),
    );
    if (shot == _Shot.blurry) {
      scene = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: scene,
      );
    }

    return Semantics(
      label: '${ok ? 'Good' : 'Bad'} photo: $caption',
      excludeSemantics: true,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  scene,
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 26,
                      height: 26,
                      color: color,
                      child: Icon(
                        ok ? Icons.check : Icons.close,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 17 / 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A lit cigarette on a tinted ground, drawn on a 100-unit square that
/// fits the frame. [far] shrinks it to a speck.
class _ScenePainter extends CustomPainter {
  const _ScenePainter({required this.far});

  final bool far;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ScopeTheme.tint);

    final unit = (size.width < size.height ? size.width : size.height) / 100;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(unit * (far ? 0.32 : 1));
    canvas.translate(-50, -50);

    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    const tip = Offset(22, 72);
    const end = Offset(66, 44);
    canvas.drawLine(tip, end, stroke(const Color(0xFF0B2F2C), 11));
    canvas.drawLine(tip, end, stroke(Colors.white, 7));
    canvas.drawLine(
      tip,
      const Offset(34, 64.4),
      stroke(const Color(0xFFE8B36A), 7),
    );
    canvas.drawCircle(
      const Offset(68, 43),
      5.5,
      Paint()..color = ScopeTheme.violation,
    );
    canvas.drawCircle(
      const Offset(68.5, 42.5),
      2.5,
      Paint()..color = const Color(0xFFFF5A4E),
    );

    final smoke = Path()
      ..moveTo(72, 36)
      ..relativeCubicTo(-4, -4, 4, -7, 0, -11)
      ..relativeCubicTo(-4, -4, 4, -7, 0, -11);
    canvas.drawPath(
      smoke,
      stroke(const Color(0xFF94A3B8), 3)..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.far != far;
}

// ---------------------------------------------------------------------------
// 4 · Privacy
// ---------------------------------------------------------------------------

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  static const _neverAsked = [
    (Icons.person_outline, 'name'),
    (Icons.phone_iphone, 'phone'),
    (Icons.mail_outline, 'email'),
    (Icons.account_circle_outlined, 'account'),
  ];

  @override
  Widget build(BuildContext context) {
    return _Card(
      children: [
        const _Tag('Privacy'),
        const _Heading('You stay anonymous'),
        const _Lead('SCOPE never asks who you are.'),
        _TwoUp(
          children: [
            for (final (icon, what) in _neverAsked)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: ScopeTheme.tint,
                  border: Border.all(color: ScopeTheme.teal100),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    CustomPaint(
                      foregroundPainter: const _SlashPainter(),
                      child: Icon(icon, color: ScopeTheme.primary, size: 32),
                    ),
                    const SizedBox(height: Gap.sm),
                    Text(
                      'No $what',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const Column(
          children: [
            _InfoRow(
              filled: false,
              leading: Icon(
                Icons.lock_outline,
                color: ScopeTheme.primary,
                size: 22,
              ),
              text: TextSpan(
                children: [
                  TextSpan(text: 'Photos and location are seen '),
                  TextSpan(text: 'only by authorised officers.', style: _bold),
                ],
              ),
            ),
            SizedBox(height: 10),
            _InfoRow(
              filled: false,
              leading: Icon(
                Icons.visibility_off_outlined,
                color: ScopeTheme.primary,
                size: 22,
              ),
              text: TextSpan(
                text: 'Keep bystanders, children, IDs and plates out of shot.',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The red strike across a "never asked" icon, with a tint halo so it reads
/// over the icon's strokes.
class _SlashPainter extends CustomPainter {
  const _SlashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final a = Offset(size.width * 0.12, size.height * 0.12);
    final b = Offset(size.width * 0.88, size.height * 0.88);
    Paint line(Color color, double width) => Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, line(ScopeTheme.tint, size.width * 0.19));
    canvas.drawLine(a, b, line(ScopeTheme.violation, size.width * 0.09));
  }

  @override
  bool shouldRepaint(_SlashPainter old) => false;
}

// ---------------------------------------------------------------------------
// 5 · After you submit
// ---------------------------------------------------------------------------

class _AfterSubmitCard extends StatelessWidget {
  const _AfterSubmitCard();

  static const _steps = [
    (
      Icons.fact_check_outlined,
      'Evidence auto-checked',
      'Only genuine evidence gets filed.',
    ),
    (Icons.tag, 'You get a reference no.', 'Save it — it’s your only record.'),
    (
      Icons.desktop_windows_outlined,
      'Officers see it',
      'It helps decide where they patrol.',
    ),
    (
      Icons.notifications_off_outlined,
      'That’s it',
      'No status to track. No one will contact you.',
    ),
  ];

  /// The reference number is the reporter's only record, so it stands out.
  static const _highlighted = 1;

  @override
  Widget build(BuildContext context) {
    return _Card(
      children: [
        const _Tag('After you submit'),
        const _Heading('What happens next'),
        Column(
          children: [
            for (var i = 0; i < _steps.length; i++)
              _TimelineStep(
                icon: _steps[i].$1,
                title: _steps[i].$2,
                detail: _steps[i].$3,
                done: i < _steps.length - 1,
                last: i == _steps.length - 1,
                highlighted: i == _highlighted,
              ),
          ],
        ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.icon,
    required this.title,
    required this.detail,
    required this.done,
    required this.last,
    required this.highlighted,
  });

  final IconData icon;
  final String title;
  final String detail;

  /// Filled marker; the final "that's it" step is drawn hollow.
  final bool done;
  final bool last;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: done ? ScopeTheme.primary : Colors.white,
                    border: Border.all(color: ScopeTheme.primary, width: 2),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: done ? Colors.white : ScopeTheme.primary,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: ScopeTheme.teal100),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: Gap.sm),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
              decoration: BoxDecoration(
                color: highlighted ? const Color(0xFFFFF8E6) : null,
                border: Border.all(
                  color: highlighted
                      ? const Color(0xFFF2D48A)
                      : Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 21 / 15,
                      color: ScopeTheme.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
