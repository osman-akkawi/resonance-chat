import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/theme.dart';
import '../engine/connectivity_battery.dart';

/// Live graph showing Φ_eff(t) and M(t) over time
class ResonanceGraph extends StatelessWidget {
  final List<BatterySnapshot> history;

  const ResonanceGraph({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.length < 2) {
      return Container(
        height: 220,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.surfaceLight),
        ),
        child: const Center(
          child: Text(
            'Collecting data points...',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    // Take last 120 points (4 minutes)
    final data = history.length > 120
        ? history.sublist(history.length - 120)
        : history;

    final phiSpots = <FlSpot>[];
    final mSpots = <FlSpot>[];
    final rSpots = <FlSpot>[];

    for (int i = 0; i < data.length; i++) {
      final x = i.toDouble();
      phiSpots.add(FlSpot(x, data[i].phiEff.clamp(0, 200)));
      mSpots.add(FlSpot(x, data[i].mBattery.clamp(0, 200)));
      rSpots.add(FlSpot(x, data[i].resonance.clamp(0, 120)));
    }

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceLight.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legend
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Row(
              children: [
                _LegendDot(color: AppColors.resonancePrimary, label: 'Φ_eff(t)'),
                const SizedBox(width: 12),
                _LegendDot(color: AppColors.energyCyan, label: 'M(t)'),
                const SizedBox(width: 12),
                _LegendDot(color: AppColors.energyAmber, label: 'R(t)'),
              ],
            ),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 50,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: AppColors.surfaceLight.withOpacity(0.3),
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 35,
                      interval: 50,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (data.length - 1).toDouble(),
                minY: 0,
                maxY: 200,
                lineBarsData: [
                  // Φ_eff(t)
                  LineChartBarData(
                    spots: phiSpots,
                    isCurved: true,
                    color: AppColors.resonancePrimary,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.resonancePrimary.withOpacity(0.08),
                    ),
                  ),
                  // M(t)
                  LineChartBarData(
                    spots: mSpots,
                    isCurved: true,
                    color: AppColors.energyCyan,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.energyCyan.withOpacity(0.05),
                    ),
                  ),
                  // R(t)
                  LineChartBarData(
                    spots: rSpots,
                    isCurved: true,
                    color: AppColors.energyAmber,
                    barWidth: 1.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    dashArray: [5, 3],
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.surfaceLight,
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final labels = ['Φ_eff', 'M(t)', 'R(t)'];
                        return LineTooltipItem(
                          '${labels[spot.barIndex]}: ${spot.y.toStringAsFixed(1)}',
                          TextStyle(
                            color: spot.bar.color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
              duration: const Duration(milliseconds: 200),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color.withOpacity(0.8),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
