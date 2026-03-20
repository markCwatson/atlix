import 'package:flutter/material.dart';

import 'package:monyx/../core/theme/app_theme.dart';
import 'package:monyx/features/ballistics/models/ballistic_solution.dart';

/// Primary field-use ballistic solution display.
///
/// Designed for maximum readability outdoors:
/// - Large orange numbers for critical corrections
/// - High-contrast dark background
/// - Logical grouping: elevation / wind / terminal
class SolutionCard extends StatelessWidget {
  const SolutionCard({super.key, required this.solution});

  final BallisticSolution solution;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            color: AppTheme.primaryOrange,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              const Icon(Icons.adjust, color: Colors.black, size: 20),
              const SizedBox(width: 8),
              Text(
                'SOLUTION  ${solution.rangeYards.toStringAsFixed(0)} YDS',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),

        // ── Body ──────────────────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // ── Elevation ──────────────────────────────────────────────────
              _SectionRow(
                icon: Icons.arrow_upward,
                iconColor: AppTheme.primaryOrange,
                label: 'ELEVATION',
                child: _ElevationGroup(solution: solution),
              ),

              const _Divider(),

              // ── Wind ──────────────────────────────────────────────────────
              _SectionRow(
                icon: Icons.air,
                iconColor: const Color(0xFF64B5F6),
                label: 'WIND',
                child: _WindGroup(solution: solution),
              ),

              const _Divider(),

              // ── Drop ──────────────────────────────────────────────────────
              _SectionRow(
                icon: Icons.south,
                iconColor: AppTheme.textSecondary,
                label: 'DROP',
                child: _BigValue(
                  value: '${solution.dropInches.toStringAsFixed(1)}"',
                  label: 'below LOS',
                ),
              ),

              const _Divider(),

              // ── Spin drift ────────────────────────────────────────────────
              if (solution.spinDriftInches.abs() > 0.1) ...[
                _SectionRow(
                  icon: Icons.rotate_right,
                  iconColor: AppTheme.textSecondary,
                  label: 'SPIN DRIFT',
                  child: _BigValue(
                    value: '${solution.spinDriftInches.toStringAsFixed(1)}"',
                    label: 'right (RH twist)',
                  ),
                ),
                const _Divider(),
              ],

              // ── Terminal ──────────────────────────────────────────────────
              _SectionRow(
                icon: Icons.speed,
                iconColor: const Color(0xFFA5D6A7),
                label: 'TERMINAL',
                child: _TerminalGroup(solution: solution),
              ),

              const SizedBox(height: 12),

              // ── Assumptions ───────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.darkBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  solution.assumptions,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Elevation group ────────────────────────────────────────────────────────────

class _ElevationGroup extends StatelessWidget {
  const _ElevationGroup({required this.solution});
  final BallisticSolution solution;

  @override
  Widget build(BuildContext context) {
    final moa = solution.elevationCorrectionMoa;
    final mil = solution.elevationCorrectionMil;
    final clicks = solution.elevationClicksUp;
    final dir = moa >= 0 ? '▲ UP' : '▼ DN';
    final moaStr = '${moa.abs().toStringAsFixed(2)} MOA';
    final milStr = '${mil.abs().toStringAsFixed(2)} mil';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$dir  $moaStr',
          style: const TextStyle(
            color: AppTheme.primaryOrange,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          '$milStr  •  $clicks clicks',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}

// ── Wind group ─────────────────────────────────────────────────────────────────

class _WindGroup extends StatelessWidget {
  const _WindGroup({required this.solution});
  final BallisticSolution solution;

  @override
  Widget build(BuildContext context) {
    final moa = solution.windCorrectionMoa;
    final mil = solution.windCorrectionMil;
    final clicks = solution.windClicksLeft;
    final drift = solution.windDriftInches;

    if (moa.abs() < 0.01) {
      return const Text(
        'No correction',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
      );
    }

    final dir = moa >= 0 ? '◀ LEFT' : '▶ RIGHT';
    final moaStr = '${moa.abs().toStringAsFixed(2)} MOA';
    final milStr = '${mil.abs().toStringAsFixed(2)} mil';
    final driftStr = '${drift.abs().toStringAsFixed(1)}" drift';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$dir  $moaStr',
          style: const TextStyle(
            color: Color(0xFF64B5F6),
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          '$milStr  •  ${clicks.abs()} clicks  •  $driftStr',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}

// ── Terminal group ─────────────────────────────────────────────────────────────

class _TerminalGroup extends StatelessWidget {
  const _TerminalGroup({required this.solution});
  final BallisticSolution solution;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _SmallStat(
          label: 'VEL',
          value:
              '${solution.remainingVelocityFps.toStringAsFixed(0)} fps',
        ),
        const SizedBox(width: 16),
        _SmallStat(
          label: 'ENERGY',
          value:
              '${solution.remainingEnergyFtLbs.toStringAsFixed(0)} ft·lb',
        ),
        const SizedBox(width: 16),
        _SmallStat(
          label: 'ToF',
          value: '${solution.timeOfFlightSeconds.toStringAsFixed(3)} s',
        ),
      ],
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(child: Align(alignment: Alignment.centerRight, child: child)),
        ],
      ),
    );
  }
}

class _BigValue extends StatelessWidget {
  const _BigValue({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

class _SmallStat extends StatelessWidget {
  const _SmallStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(color: AppTheme.dividerColor, height: 1);
  }
}
