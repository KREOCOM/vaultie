import 'package:flutter/material.dart';

import '../../theme/vaultie_theme.dart';

/// One answer option: a colored rounded-square badge with a custom glyph + label.
/// The badge style (colored rounded-square + white glyph) is the app standard —
/// never emoji, never default Material icons.
class DiagOption {
  const DiagOption({required this.color, required this.glyph, required this.label});
  final Color color;
  final String glyph;
  final String label;
}

/// Screen 4 — Diagnostic. A question with 2–3 answer cards grouped with the
/// question (no empty middle). Tapping a card selects it, then advances.
class DiagnosticScreen extends StatefulWidget {
  const DiagnosticScreen({
    super.key,
    required this.question,
    required this.options,
    required this.segmentsFilled,
    required this.onSelected,
    this.scene,
    this.onBack,
    this.initiallySelected,
  });

  final String question;
  final List<DiagOption> options;
  final int segmentsFilled;
  final void Function(int index) onSelected;

  /// Per-question composed scene shown above the question (replaces the logo).
  final Widget? scene;
  final VoidCallback? onBack;

  /// Preview-only: render a card already selected.
  final int? initiallySelected;

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  int? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initiallySelected;
  }

  void _pick(int i) {
    if (_selected != null) return;
    setState(() => _selected = i);
    Future.delayed(const Duration(milliseconds: 320), () {
      if (mounted) widget.onSelected(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return VtScaffold(
      onBack: widget.onBack,
      segments: 4,
      segmentsFilled: widget.segmentsFilled,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.scene != null) ...[
            widget.scene!,
            const SizedBox(height: 30),
          ],
          Text(
            widget.question,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: VT.ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 30),
          for (var i = 0; i < widget.options.length; i++) ...[
            _AnswerCard(
              option: widget.options[i],
              selected: _selected == i,
              onTap: () => _pick(i),
            ),
            if (i < widget.options.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final DiagOption option;
  final bool selected;
  final VoidCallback onTap;

  static const _selBg = Color(0xFFF3F8F4);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? _selBg : VT.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? VT.brand : const Color(0x00000000),
              width: 2,
            ),
            boxShadow: selected ? null : VT.softShadow,
          ),
          child: Row(
            children: [
              _Badge(color: option.color, glyph: option.glyph),
              const SizedBox(width: 14),
              Expanded(
                child: Text(option.label,
                    style: const TextStyle(
                        color: VT.ink,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700)),
              ),
              if (selected)
                const Text('✓',
                    style: TextStyle(
                        color: VT.brand,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

/// App-standard badge: colored rounded-square (36×36, radius 10) + white glyph.
class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.glyph});
  final Color color;
  final String glyph;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.16)!, color],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.30),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(glyph,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.0)),
        ),
      ),
    );
  }
}
