import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../engine/connectivity_battery.dart';
import '../services/connectivity_service.dart';
import '../widgets/resonance_graph.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<ConnectivityBatteryEngine>();
    final connectivity = context.watch<ConnectivityService>();
    final effectiveOnline = connectivity.isOnline && !engine.isForceOffline;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('RESONANCE DASHBOARD'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Live Graph ──
            const _SectionTitle('LIVE RESONANCE FIELD'),
            const SizedBox(height: 8),
            ResonanceGraph(history: engine.history),
            const SizedBox(height: 24),

            // ── Equations Panel ──
            const _SectionTitle('EQUATION VALUES'),
            const SizedBox(height: 8),
            _EquationCard(
              title: 'Φ_eff(t) — Effective Connectivity',
              formula:
                  'Φ_eff(t) = Φ(t) + R(t) ⋅ (1 + ∫₀ᵗ ρ(s)⋅Π(s) ds)',
              value: engine.currentPhiEff,
              unit: '',
              color: AppColors.resonancePrimary,
              maxValue: 200,
            ),
            const SizedBox(height: 8),
            _EquationCard(
              title: 'EOC(t) — Effective Offline Connectivity',
              formula: 'EOC(t) = αC + βT + γP + δF − μD − νU',
              value: engine.currentEOC * 100,
              unit: '%',
              color: AppColors.energyGreen,
              maxValue: 100,
            ),
            const SizedBox(height: 8),
            _EquationCard(
              title: 'M(t) — Messaging Battery',
              formula: 'M(t) = S + K + Q + R − D − L',
              value: engine.currentM,
              unit: '',
              color: AppColors.energyCyan,
              maxValue: 200,
            ),
            const SizedBox(height: 8),
            _EquationCard(
              title: 'R(t) — Resonance Charge',
              formula: 'R₀ = 120 presence-joules',
              value: engine.currentResonance,
              unit: ' pJ',
              color: AppColors.energyAmber,
              maxValue: 120,
            ),
            const SizedBox(height: 24),

            // ── Parameters ──
            const _SectionTitle('EOC PARAMETERS'),
            const SizedBox(height: 8),
            _ParamGrid(params: {
              'C (cached)': engine.eocParams.cachedContent.toStringAsFixed(2),
              'T (trust)': engine.eocParams.trustToken.toStringAsFixed(2),
              'P (presence)': engine.eocParams.presence.toStringAsFixed(2),
              'F (bond)': engine.eocParams.friendshipBond.toStringAsFixed(2),
              'D (disconnect)':
                  '${engine.eocParams.disconnectDur.toStringAsFixed(1)} min',
              'U (uncertainty)':
                  engine.eocParams.uncertainty.toStringAsFixed(3),
            }),
            const SizedBox(height: 16),

            const _SectionTitle('BATTERY PARAMETERS'),
            const SizedBox(height: 8),
            _ParamGrid(params: {
              'S (semantic)': engine.mParams.semanticReservoir.toStringAsFixed(1),
              'K (envelopes)': engine.mParams.keyEnvelopeStock.toStringAsFixed(1),
              'Q (queue)': engine.mParams.queueDepthReserve.toStringAsFixed(1),
              'R (resonance)': engine.mParams.resonanceCharge.toStringAsFixed(1),
              'D (decay)': engine.mParams.decay.toStringAsFixed(2),
              'L (loss)': engine.mParams.loss.toStringAsFixed(2),
            }),
            const SizedBox(height: 24),

            // ── Status ──
            const _SectionTitle('SYSTEM STATUS'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceLight.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  _StatusRow(
                    'Network Status',
                    effectiveOnline ? 'CONNECTED' : 'OFFLINE',
                    effectiveOnline ? AppColors.energyGreen : AppColors.energyRed,
                  ),
                  _StatusRow(
                    'Force Offline',
                    engine.isForceOffline ? 'ACTIVE' : 'INACTIVE',
                    engine.isForceOffline
                        ? AppColors.energyAmber
                        : AppColors.textMuted,
                  ),
                  _StatusRow(
                    'Queued Messages',
                    '${engine.queuedCount}',
                    engine.queuedCount > 0
                        ? AppColors.resonanceSecondary
                        : AppColors.textMuted,
                  ),
                  _StatusRow(
                    'Dictionary Size',
                    '${engine.compressor.dictionarySize} phrases',
                    AppColors.energyCyan,
                  ),
                  _StatusRow(
                    'History Points',
                    '${engine.history.length}',
                    AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Testing Controls ──
            const _SectionTitle('TESTING CONTROLS'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceLight.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  // Force offline toggle
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        engine.setForceOffline(!engine.isForceOffline);
                      },
                      icon: Icon(
                        engine.isForceOffline
                            ? Icons.wifi
                            : Icons.airplanemode_active,
                      ),
                      label: Text(
                        engine.isForceOffline
                            ? 'Disable Force Offline'
                            : 'Enable Force Offline',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: engine.isForceOffline
                            ? AppColors.energyGreen
                            : AppColors.energyAmber,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Recharge button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        engine.performChargingRitual(
                          recentMessages: [
                            'hello', 'how are you', 'see you later',
                            'good morning', 'thanks', 'bye',
                          ],
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('⚡ Resonance recharged!'),
                            backgroundColor: AppColors.energyGreen,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.bolt),
                      label: const Text('Quick Recharge'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.resonancePrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
      ),
    );
  }
}

class _EquationCard extends StatelessWidget {
  final String title;
  final String formula;
  final double value;
  final String unit;
  final Color color;
  final double maxValue;

  const _EquationCard({
    required this.title,
    required this.formula,
    required this.value,
    required this.unit,
    required this.color,
    required this.maxValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${value.toStringAsFixed(1)}$unit',
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            formula,
            style: TextStyle(
              color: AppColors.textMuted.withOpacity(0.6),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (value / maxValue).clamp(0.0, 1.0),
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParamGrid extends StatelessWidget {
  final Map<String, String> params;
  const _ParamGrid({required this.params});

  @override
  Widget build(BuildContext context) {
    final entries = params.entries.toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight.withOpacity(0.5)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: entries.map((e) {
          return Container(
            width: (MediaQuery.of(context).size.width - 72) / 3,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight.withOpacity(0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  e.key,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  e.value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatusRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
