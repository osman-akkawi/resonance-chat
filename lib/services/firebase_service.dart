import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';

/// Singleton Firebase service — shared across all screens.
/// Use FirebaseService.instance everywhere instead of creating new instances.
class FirebaseService {
  // Singleton
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
      try {
        await _firestore.collection('users').doc(currentUser!.uid).update({
          'isOnline': false,
          'lastSeen': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
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

  Future<void> sendMessage(ChatMessage message) async {
    final roomId = _chatRoomId(message.senderId, message.receiverId);
    await _firestore
        .collection('chats')
        .doc(roomId)
        .collection('messages')
        .doc(message.id)
        .set(message.toFirestore());

    await _firestore.collection('chats').doc(roomId).set({
      'participants': [message.senderId, message.receiverId],
      'lastMessage': message.content,
      'lastMessageTime': message.timestamp.toIso8601String(),
      'lastSenderId': message.senderId,
    }, SetOptions(merge: true));
  }

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

  Future<int> syncOfflineMessages(List<ChatMessage> messages) async {
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
