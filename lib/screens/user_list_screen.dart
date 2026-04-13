import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../engine/connectivity_battery.dart';
import '../services/firebase_service.dart';
import '../services/connectivity_service.dart';
import '../models/models.dart';
import '../widgets/battery_indicator.dart';
import 'chat_screen.dart';
import 'dashboard_screen.dart';

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final _firebase = FirebaseService();

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<ConnectivityBatteryEngine>();
    final connectivity = context.watch<ConnectivityService>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('RESONANCE'),
        actions: [
          // Force Offline toggle
          IconButton(
            icon: Icon(
              engine.isForceOffline
                  ? Icons.airplanemode_active
                  : Icons.airplanemode_inactive,
              color: engine.isForceOffline
                  ? AppColors.energyAmber
                  : AppColors.textMuted,
            ),
            tooltip: 'Force Offline',
            onPressed: () {
              engine.setForceOffline(!engine.isForceOffline);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    engine.isForceOffline
                        ? '✈ Force Offline: ON — Simulating zero connectivity'
                        : '📶 Force Offline: OFF — Back to real connectivity',
                  ),
                  backgroundColor: engine.isForceOffline
                      ? AppColors.energyAmber
                      : AppColors.energyGreen,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),
          // Dashboard
          IconButton(
            icon: const Icon(Icons.analytics_outlined,
                color: AppColors.resonanceSecondary),
            tooltip: 'Resonance Dashboard',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DashboardScreen(),
                ),
              );
            },
          ),
          // Sign out
          IconButton(
            icon:
                const Icon(Icons.logout, color: AppColors.textMuted, size: 20),
            onPressed: () async {
              engine.stopEngine();
              await _firebase.signOut();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Resonance bar
          ResonanceFieldBar(
            phiEff: engine.currentPhiEff,
            mBattery: engine.currentM,
            resonance: engine.currentResonance,
            isOnline: connectivity.isOnline,
            forceOffline: engine.isForceOffline,
          ),
          const SizedBox(height: 8),

          // Users list
          Expanded(
            child: StreamBuilder<List<AppUser>>(
              stream: _firebase.streamOtherUsers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.resonancePrimary,
                    ),
                  );
                }

                final users = snapshot.data ?? [];
                if (users.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: AppColors.textMuted.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No other users yet',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create a second test account\nto start chatting',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textMuted.withOpacity(0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return _UserTile(
                      user: user,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(otherUser: user),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final AppUser user;
  final VoidCallback onTap;

  const _UserTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.surfaceLight.withOpacity(0.5),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: AppColors.resonanceGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  user.displayName.isNotEmpty
                      ? user.displayName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Online indicator
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: user.isOnline
                    ? AppColors.energyGreen
                    : AppColors.textMuted.withOpacity(0.3),
                boxShadow: user.isOnline
                    ? [
                        BoxShadow(
                          color: AppColors.energyGreen.withOpacity(0.4),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
