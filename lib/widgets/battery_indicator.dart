import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Animated circular resonance battery indicator
class ResonanceBatteryIndicator extends StatefulWidget {
  final double reservePercent;
  final double phiEff;
  final double mBattery;
  final bool isOnline;

  const ResonanceBatteryIndicator({
    super.key,
    required this.reservePercent,
    required this.phiEff,
    required this.mBattery,
    required this.isOnline,
  });

  @override
  State<ResonanceBatteryIndicator> createState() => _ResonanceBatteryIndicatorState();
}

class _ResonanceBatteryIndicatorState extends State<ResonanceBatteryIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Color get _batteryColor {
    if (widget.reservePercent > 60) return AppColors.energyGreen;
    if (widget.reservePercent > 30) return AppColors.energyAmber;
    return AppColors.energyRed;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, child) {
        final pulse = 0.95 + _pulseCtrl.value * 0.05;
        return Transform.scale(
          scale: pulse,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _batteryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _batteryColor.withOpacity(0.4),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _batteryColor.withOpacity(0.2),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Battery icon
                _BatteryIcon(
                  percent: widget.reservePercent,
                  color: _batteryColor,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${widget.reservePercent.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: _batteryColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      widget.isOnline ? 'LIVE' : 'RESONANCE',
                      style: TextStyle(
                        color: _batteryColor.withOpacity(0.7),
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BatteryIcon extends StatelessWidget {
  final double percent;
  final Color color;

  const _BatteryIcon({required this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(28, 14),
      painter: _BatteryPainter(percent: percent, color: color),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  final double percent;
  final Color color;

  _BatteryPainter({required this.percent, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = color.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Battery body
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width - 3, size.height),
      const Radius.circular(3),
    );
    canvas.drawRRect(body, borderPaint);

    // Battery tip
    final tip = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width - 3, size.height * 0.25, 3, size.height * 0.5),
      const Radius.circular(1),
    );
    canvas.drawRRect(tip, Paint()..color = color.withOpacity(0.6));

    // Fill
    final fillWidth = (size.width - 6) * (percent / 100).clamp(0.0, 1.0);
    if (fillWidth > 0) {
      final fill = RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 2, fillWidth, size.height - 4),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(fill, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _BatteryPainter old) =>
      old.percent != percent || old.color != color;
}

/// Floating resonance field indicator (used in chat screen top bar)
class ResonanceFieldBar extends StatelessWidget {
  final double phiEff;
  final double mBattery;
  final double resonance;
  final bool isOnline;
  final bool forceOffline;

  const ResonanceFieldBar({
    super.key,
    required this.phiEff,
    required this.mBattery,
    required this.resonance,
    required this.isOnline,
    required this.forceOffline,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (phiEff / 200 * 100).clamp(0.0, 100.0);
    final color = percent > 60
        ? AppColors.energyGreen
        : percent > 30
            ? AppColors.energyAmber
            : AppColors.energyRed;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                forceOffline
                    ? Icons.airplanemode_active
                    : isOnline
                        ? Icons.wifi
                        : Icons.wifi_off,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                forceOffline
                    ? 'FORCE OFFLINE'
                    : isOnline
                        ? 'CONNECTED'
                        : 'OFFLINE — RESONANCE ACTIVE',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              ResonanceBatteryIndicator(
                reservePercent: percent,
                phiEff: phiEff,
                mBattery: mBattery,
                isOnline: isOnline && !forceOffline,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Stat('Φ_eff', phiEff.toStringAsFixed(1), color),
              _Stat('M(t)', mBattery.toStringAsFixed(1), AppColors.energyCyan),
              _Stat('R(t)', resonance.toStringAsFixed(1), AppColors.resonanceSecondary),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Stat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: color.withOpacity(0.6),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
