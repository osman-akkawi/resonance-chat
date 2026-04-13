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
          // Connection status indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connectivity.isOnline
                        ? AppColors.energyGreen
                        : Colors.red,
                    boxShadow: connectivity.isOnline
                        ? [
                            BoxShadow(
                              color: AppColors.energyGreen.withOpacity(0.4),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  connectivity.isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 11,
                    color: connectivity.isOnline
                        ? AppColors.energyGreen
                        : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
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
            forceOffline: !connectivity.isOnline,
          ),

          // Offline warning banner
          if (!connectivity.isOnline)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.airplanemode_active,
                      color: Colors.redAccent, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You are offline. Messages will queue locally and sync when connected.',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 4),

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

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48,
                            color: Colors.red.withOpacity(0.5)),
                        const SizedBox(height: 12),
                        const Text(
                          'Error loading users',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${snapshot.error}',
                          style: TextStyle(
                            color: AppColors.textMuted.withOpacity(0.6),
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Retry'),
                        ),
                      ],
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
                          'Sign up with a different email\non another device to start chatting',
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
