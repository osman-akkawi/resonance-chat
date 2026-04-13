import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../engine/connectivity_battery.dart';
import '../services/connectivity_service.dart';
import '../services/firebase_service.dart';
import 'user_list_screen.dart';

class ChargingRitualScreen extends StatefulWidget {
  const ChargingRitualScreen({super.key});

  @override
  State<ChargingRitualScreen> createState() => _ChargingRitualScreenState();
}

class _ChargingRitualScreenState extends State<ChargingRitualScreen>
    with TickerProviderStateMixin {
  final _firebase = FirebaseService();
  late AnimationController _glowCtrl;
  late AnimationController _chargeCtrl;
  late Animation<double> _chargeProgress;

  bool _isCharging = false;
  bool _isCharged = false;
  String _statusText = 'Detecting connectivity...';
  double _chargePercent = 0;
  int _dictSize = 0;
  int _envelopes = 0;
  int _cachedChats = 0;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _chargeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    _chargeProgress = CurvedAnimation(
      parent: _chargeCtrl,
      curve: Curves.easeInOutCubic,
    );
    _chargeProgress.addListener(() {
      setState(() {
        _chargePercent = _chargeProgress.value * 100;
      });
    });

    // Check connectivity after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndCharge();
    });
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _chargeCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAndCharge() async {
    final connectivity = context.read<ConnectivityService>();
    final engine = context.read<ConnectivityBatteryEngine>();

    // Step 1: Detect WiFi
    setState(() => _statusText = 'Scanning network...');
    await Future.delayed(const Duration(milliseconds: 800));

    if (connectivity.hasWifi || connectivity.isOnline) {
      setState(() => _statusText = '✓ Strong connection detected');
    } else {
      setState(() =>
          _statusText = '⚠ No WiFi — connect to WiFi for best charge');
    }
    await Future.delayed(const Duration(milliseconds: 600));

    // Step 2: Pre-load chats
    setState(() {
      _statusText = 'Pre-loading recent chats from Firestore...';
      _isCharging = true;
    });

    List<String> recentTexts = [];
    try {
      final users = await _firebase.getOtherUsers();
      for (final user in users) {
        final texts = await _firebase.getRecentMessageTexts(user.uid);
        recentTexts.addAll(texts);
      }
      _cachedChats = recentTexts.length;
    } catch (e) {
      // Offline — use defaults
      _cachedChats = 0;
    }

    setState(() => _statusText = '✓ Cached $_cachedChats messages');
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 3: Build semantic dictionary
    setState(() => _statusText = 'Building semantic dictionary...');
    await Future.delayed(const Duration(milliseconds: 600));

    engine.performChargingRitual(
      recentMessages: recentTexts.isEmpty
          ? _defaultMessages()
          : recentTexts,
      preSignedEnvelopes: 25,
    );

    _dictSize = engine.compressor.dictionarySize;
    _envelopes = 25;

    setState(
        () => _statusText = '✓ Dictionary built: $_dictSize phrases mapped');
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 4: Pre-create signed envelopes
    setState(() => _statusText = 'Pre-creating $_envelopes signed envelopes...');
    await Future.delayed(const Duration(milliseconds: 600));
    setState(() => _statusText = '✓ $_envelopes envelopes ready');
    await Future.delayed(const Duration(milliseconds: 400));

    // Step 5: Animate charge
    setState(
        () => _statusText = 'Charging Resonance field to R₀ = 120 pJ...');
    _chargeCtrl.forward();
    await _chargeCtrl.animateTo(1.0);

    setState(() {
      _isCharged = true;
      _isCharging = false;
      _statusText = '⚡ Resonance fully charged — ready for offline use';
    });

    // Start the engine
    engine.startEngine();
  }

  List<String> _defaultMessages() {
    return [
      'hello', 'hi there', 'how are you', 'good morning', 'good night',
      'see you later', 'thanks', 'thank you so much', 'okay see you',
      'on my way', 'be there soon', 'what time', 'where are you',
      'love you', 'miss you', 'good morning dear', 'take care',
      'call me when free', 'sure no problem', 'sounds good',
      'let me know', 'i will be late', 'wait for me',
      'how are you doing', 'i am fine', 'are you free tonight',
      'coming soon', 'good afternoon', 'good evening',
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0A0E1A),
              Color(0xFF0F172A),
              Color(0xFF0A0E1A),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Title
                const Text(
                  '🏠 HOME CHARGING RITUAL',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Preparing your Resonance field',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary.withOpacity(0.6),
                  ),
                ),
                const Spacer(),

                // Charging orb
                AnimatedBuilder(
                  animation: _glowCtrl,
                  builder: (context, child) {
                    final glow = 0.3 + _glowCtrl.value * 0.4;
                    return Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _isCharged
                                ? AppColors.energyGreen.withOpacity(glow)
                                : AppColors.resonancePrimary.withOpacity(glow),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: _isCharged
                                  ? [
                                      AppColors.energyGreen.withOpacity(0.3),
                                      AppColors.energyGreen.withOpacity(0.1),
                                    ]
                                  : [
                                      AppColors.resonancePrimary
                                          .withOpacity(0.3),
                                      AppColors.resonanceGlow.withOpacity(0.1),
                                    ],
                            ),
                            border: Border.all(
                              color: _isCharged
                                  ? AppColors.energyGreen.withOpacity(0.5)
                                  : AppColors.resonancePrimary.withOpacity(0.4),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (_isCharged
                                        ? AppColors.energyGreen
                                        : AppColors.resonancePrimary)
                                    .withOpacity(0.3),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${_chargePercent.toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w700,
                                  color: _isCharged
                                      ? AppColors.energyGreen
                                      : AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                _isCharged ? 'CHARGED' : 'CHARGING',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2,
                                  color: _isCharged
                                      ? AppColors.energyGreen.withOpacity(0.7)
                                      : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),

                // Status text
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _statusText,
                    key: ValueKey(_statusText),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: _isCharged
                          ? AppColors.energyGreen
                          : AppColors.textSecondary,
                      fontWeight:
                          _isCharged ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Stats cards
                if (_isCharging || _isCharged)
                  Row(
                    children: [
                      _StatCard(
                        icon: Icons.compress,
                        label: 'Dictionary',
                        value: '$_dictSize phrases',
                        color: AppColors.energyCyan,
                      ),
                      const SizedBox(width: 8),
                      _StatCard(
                        icon: Icons.mail_outline,
                        label: 'Envelopes',
                        value: '$_envelopes ready',
                        color: AppColors.resonanceSecondary,
                      ),
                      const SizedBox(width: 8),
                      _StatCard(
                        icon: Icons.bolt,
                        label: 'R₀',
                        value: '120 pJ',
                        color: AppColors.energyAmber,
                      ),
                    ],
                  ),

                const Spacer(),

                // Continue button
                if (_isCharged) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const UserListScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.energyGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bolt, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Enter Resonance Chat',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
