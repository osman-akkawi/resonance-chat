import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Network isolation for Force Offline ──
  bool _networkDisabled = false;

  /// Disable Firestore network access — forces all reads to come from
  /// local cache only, and prevents any writes from reaching the server.
  /// This is critical for the Force Offline testing mode.
  Future<void> disableNetwork() async {
    if (!_networkDisabled) {
      await _firestore.disableNetwork();
      _networkDisabled = true;
    }
  }

  /// Re-enable Firestore network access — queued writes will flush
  /// and snapshots will sync from the server.
  Future<void> enableNetwork() async {
    if (_networkDisabled) {
      await _firestore.enableNetwork();
      _networkDisabled = false;
    }
  }

  bool get isNetworkDisabled => _networkDisabled;

  // ── Auth ──
  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<User?> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (cred.user != null) {
      await _firestore.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'email': email,
        'displayName': email.split('@').first,
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    return cred.user;
  }

  Future<User?> signUp(String email, String password, String name) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (cred.user != null) {
      await cred.user!.updateDisplayName(name);
      await _firestore.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'email': email,
        'displayName': name,
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }
    return cred.user;
  }

  Future<void> signOut() async {
    if (currentUser != null) {
      await _firestore.collection('users').doc(currentUser!.uid).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }
    await _auth.signOut();
  }

  // ── Users ──
  Future<List<AppUser>> getOtherUsers() async {
    final snap = await _firestore.collection('users').get();
    return snap.docs
        .map((d) => AppUser.fromFirestore(d.data()))
        .where((u) => u.uid != currentUser?.uid)
        .toList();
  }

  Stream<List<AppUser>> streamOtherUsers() {
    return _firestore.collection('users').snapshots().map((snap) {
      return snap.docs
          .map((d) => AppUser.fromFirestore(d.data()))
          .where((u) => u.uid != currentUser?.uid)
          .toList();
    });
  }

  // ── Chat ──
  String _chatRoomId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Send a message to Firestore.
  /// IMPORTANT: Callers must check force-offline BEFORE calling this.
  /// If Firestore network is disabled, this write will be queued locally
  /// by Firestore's own offline persistence and flushed on enableNetwork().
  Future<void> sendMessage(ChatMessage message) async {
    final roomId = _chatRoomId(message.senderId, message.receiverId);
    await _firestore
        .collection('chats')
        .doc(roomId)
        .collection('messages')
        .doc(message.id)
        .set(message.toFirestore());

    // Update chat room metadata
    await _firestore.collection('chats').doc(roomId).set({
      'participants': [message.senderId, message.receiverId],
      'lastMessage': message.content,
      'lastMessageTime': message.timestamp.toIso8601String(),
      'lastSenderId': message.senderId,
    }, SetOptions(merge: true));
  }

  /// Stream messages in a chat room
  Stream<List<ChatMessage>> streamMessages(String otherUserId) {
    final myUid = currentUser?.uid ?? '';
    final roomId = _chatRoomId(myUid, otherUserId);
    return _firestore
        .collection('chats')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((d) => ChatMessage.fromFirestore(d.data()))
          .toList();
    });
  }

  /// Get recent messages for charging ritual
  Future<List<String>> getRecentMessageTexts(String otherUserId) async {
    final myUid = currentUser?.uid ?? '';
    final roomId = _chatRoomId(myUid, otherUserId);
    final snap = await _firestore
        .collection('chats')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .get();
    return snap.docs.map((d) => d.data()['content'] as String? ?? '').toList();
  }

  /// Sync queued offline messages to Firestore.
  /// IMPORTANT: Caller must ensure force-offline is NOT active before calling.
  Future<int> syncOfflineMessages(List<ChatMessage> messages) async {
    if (_networkDisabled) return 0; // safety guard
    int synced = 0;
    final batch = _firestore.batch();
    for (final msg in messages) {
      final roomId = _chatRoomId(msg.senderId, msg.receiverId);
      final ref = _firestore
          .collection('chats')
          .doc(roomId)
          .collection('messages')
          .doc(msg.id);
      batch.set(ref, msg.toFirestore());
      synced++;
    }
    if (synced > 0) {
      await batch.commit();
    }
    return synced;
  }
}
