import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/models.dart';

/// Local persistence using Hive for offline message queue and semantic dictionary
class LocalStorageService {
  static const String _messageQueueBox = 'message_queue';
  static const String _semanticDictBox = 'semantic_dict';
  static const String _settingsBox = 'settings';

  late Box _mqBox;
  late Box _sdBox;
  late Box _settingsBoxInstance;

  /// Initialize Hive
  Future<void> init() async {
    await Hive.initFlutter();
    _mqBox = await Hive.openBox(_messageQueueBox);
    _sdBox = await Hive.openBox(_semanticDictBox);
    _settingsBoxInstance = await Hive.openBox(_settingsBox);
  }

  // ── Message Queue ──

  /// Save a message to local queue
  Future<void> queueMessage(ChatMessage message) async {
    await _mqBox.put(message.id, jsonEncode(message.toFirestore()));
  }

  /// Get all queued (un-synced) messages
  List<ChatMessage> getQueuedMessages() {
    final messages = <ChatMessage>[];
    for (final key in _mqBox.keys) {
      final json = jsonDecode(_mqBox.get(key) as String);
      final msg = ChatMessage.fromFirestore(json);
      if (!msg.isSynced) {
        messages.add(msg);
      }
    }
    return messages;
  }

  /// Mark a message as synced
  Future<void> markSynced(String messageId) async {
    final raw = _mqBox.get(messageId);
    if (raw != null) {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      json['isSynced'] = true;
      await _mqBox.put(messageId, jsonEncode(json));
    }
  }

  /// Clear synced messages
  Future<void> clearSyncedMessages() async {
    final toRemove = <String>[];
    for (final key in _mqBox.keys) {
      final json = jsonDecode(_mqBox.get(key) as String);
      if (json['isSynced'] == true) {
        toRemove.add(key as String);
      }
    }
    for (final key in toRemove) {
      await _mqBox.delete(key);
    }
  }

  // ── Semantic Dictionary ──

  /// Save the semantic dictionary
  Future<void> saveSemanticDict(Map<String, String> dict) async {
    await _sdBox.clear();
    for (final entry in dict.entries) {
      await _sdBox.put(entry.key, entry.value);
    }
  }

  /// Load the semantic dictionary
  Map<String, String> loadSemanticDict() {
    final dict = <String, String>{};
    for (final key in _sdBox.keys) {
      dict[key as String] = _sdBox.get(key) as String;
    }
    return dict;
  }

  // ── Settings ──

  Future<void> saveSetting(String key, dynamic value) async {
    await _settingsBoxInstance.put(key, value);
  }

  dynamic getSetting(String key, {dynamic defaultValue}) {
    return _settingsBoxInstance.get(key, defaultValue: defaultValue);
  }
}
