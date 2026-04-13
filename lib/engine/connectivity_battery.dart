/// ============================================================================
/// CONNECTIVITY BATTERY MODEL & RESONANCE CONTINUITY ENGINE
/// ============================================================================
///
/// This file faithfully implements EVERY mathematical rule from the
/// Connectivity Battery Model and the Resonance Continuity Axiom (Rule 61).
///
/// Equations Implemented:
///   (1) EOC(t) = αC + βT + γP + δF − μD − νU
///   (2) M(t)   = S + K + Q + R − D − L
///   (3) Φ_eff(t) = Φ(t) + R(t) ⋅ (1 + ∫₀ᵗ ρ(s) ⋅ Π(s) ds)
///
/// Sub-systems:
///   - Decay timer (reduces M(t) every minute)
///   - Resonance field R(t) — boosted on any connection pulse
///   - Priority queue for message ordering
///   - Semantic compression (message = ID + delta)
///   - Predictive shadow / digital twin
///   - Pulse opportunistic sync
///   - Delayed truth ↔ perceived continuity
/// ============================================================================

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

// ─── Data point for live graph ──────────────────────────────────────────────
class BatterySnapshot {
  final DateTime time;
  final double phiEff;   // Φ_eff(t)
  final double mBattery;  // M(t)
  final double resonance; // R(t)
  final double eoc;       // EOC(t)

  BatterySnapshot({
    required this.time,
    required this.phiEff,
    required this.mBattery,
    required this.resonance,
    required this.eoc,
  });
}

// ─── EOC Parameters ─────────────────────────────────────────────────────────
/// Effective Offline Connectivity:
///   EOC(t) = αC + βT + γP + δF − μD − νU
///
///   C = cached content score       [0..1]  e.g. fraction of chat pre-loaded
///   T = trust / session token age  [0..1]  freshness of auth tokens
///   P = presence (recent activity) [0..1]
///   F = friendship / bond weight   [0..1]
///   D = disconnection duration     [0..∞)  minutes since last connectivity
///   U = uncertainty penalty        [0..1]  unverified delivery ratio
class EOCParams {
  double cachedContent;   // C
  double trustToken;      // T
  double presence;        // P
  double friendshipBond;  // F
  double disconnectDur;   // D  (minutes)
  double uncertainty;     // U

  EOCParams({
    this.cachedContent = 0.9,
    this.trustToken = 1.0,
    this.presence = 0.8,
    this.friendshipBond = 0.7,
    this.disconnectDur = 0.0,
    this.uncertainty = 0.1,
  });
}

// ─── Messaging Battery Parameters ───────────────────────────────────────────
/// Messaging Battery:
///   M(t) = S + K + Q + R − D − L
///
///   S = semantic reservoir   [0..50]  compressed messages available
///   K = key-envelope stock   [0..30]  pre-signed envelopes
///   Q = queue depth reserve  [0..40]  local queue capacity remaining
///   R = resonance charge     [0..50]  accumulated resonance energy
///   D = decay (time drain)   [0..∞)  cumulative decay since charge
///   L = loss (failed syncs)  [0..∞)  messages lost / expired
class MBatteryParams {
  double semanticReservoir;
  double keyEnvelopeStock;
  double queueDepthReserve;
  double resonanceCharge;
  double decay;
  double loss;

  MBatteryParams({
    this.semanticReservoir = 40.0,
    this.keyEnvelopeStock = 25.0,
    this.queueDepthReserve = 35.0,
    this.resonanceCharge = 50.0,
    this.decay = 0.0,
    this.loss = 0.0,
  });
}

// ─── Weight constants ───────────────────────────────────────────────────────
/// EOC weights
const double kAlpha = 0.25; // α — weight for cached content
const double kBeta  = 0.20; // β — weight for trust tokens
const double kGamma = 0.20; // γ — weight for presence
const double kDelta = 0.15; // δ — weight for friendship bond
const double kMu    = 0.02; // μ — penalty coefficient for disconnect duration
const double kNu    = 0.18; // ν — penalty coefficient for uncertainty

/// Decay rate: M(t) loses this many units per minute offline
const double kDecayPerMinute = 0.35;

/// Resonance field boost per connection pulse detected
const double kResonancePulseBoost = 8.0;

/// Resonance passive decay per minute
const double kResonancePassiveDecay = 0.15;

/// Maximum resonance charge
const double kMaxResonance = 120.0;

/// ── Resonance Axiom scaling ──
/// These control how strongly R(t) contributes to Φ_eff.
/// kResonanceScale controls the base multiplier for the R(t) term so that
/// resonance has a meaningful impact (not squashed to [0..1]).
const double kResonanceScale = 50.0;  // R(t) scaled to [0..50]
/// Maximum ∫ρΠ before clamping — prevents runaway integral
const double kIntegralCap = 5.0;

// ─── CORE EQUATIONS ─────────────────────────────────────────────────────────

/// (1) Effective Offline Connectivity
///     EOC(t) = αC + βT + γP + δF − μD − νU
double computeEOC(EOCParams p) {
  final raw = kAlpha * p.cachedContent
             + kBeta  * p.trustToken
             + kGamma * p.presence
             + kDelta * p.friendshipBond
             - kMu    * p.disconnectDur
             - kNu    * p.uncertainty;
  return raw.clamp(0.0, 1.0);
}

/// (2) Messaging Battery
///     M(t) = S + K + Q + R − D − L
double computeM(MBatteryParams p) {
  final raw = p.semanticReservoir
            + p.keyEnvelopeStock
            + p.queueDepthReserve
            + p.resonanceCharge
            - p.decay
            - p.loss;
  return raw.clamp(0.0, 200.0);
}

/// Messaging Battery as percentage (of max 200)
double computeMPercent(MBatteryParams p) {
  return (computeM(p) / 200.0 * 100.0).clamp(0.0, 100.0);
}

/// (3) Resonance Continuity Axiom (Rule 61)
///     Φ_eff(t) = Φ(t) + R(t) ⋅ (1 + ∫₀ᵗ ρ(s) ⋅ Π(s) ds)
///
///     Φ(t) = raw connectivity (we use EOC as the base, scaled to [0..100])
///     R(t) = resonance charge at time t, scaled via kResonanceScale
///     ρ(s) = resonance density at sample s  — how much resonance "field"
///            existed at moment s.  Online: ρ(s) = EOC(s). Offline: ρ(s) =
///            EOC(s) × offline_attenuation × message_activity_boost.
///     Π(s) = priority weight at sample s — boosted when messages are sent
///            (reflects user intent/urgency amplifying the field).
///
///   The integral is approximated via trapezoidal rule over historical samples.
///   The integral is capped at kIntegralCap to prevent runaway growth.
double computePhiEff({
  required double phiRaw,        // Φ(t) — raw connectivity = EOC × 100
  required double resonance,     // R(t) — [0..kMaxResonance]
  required List<double> rhoPi,   // ρ(s)⋅Π(s) samples collected over time
  required double dt,            // time step between samples (minutes)
}) {
  // Trapezoidal approximation of ∫₀ᵗ ρ(s)⋅Π(s) ds
  double integral = 0.0;
  for (int i = 1; i < rhoPi.length; i++) {
    integral += (rhoPi[i - 1] + rhoPi[i]) / 2.0 * dt;
  }
  // Cap the integral so it doesn't grow forever
  integral = integral.clamp(0.0, kIntegralCap);

  // Scale R(t) to a meaningful contribution range [0..kResonanceScale]
  // instead of normalizing to [0..1] which makes the term negligible
  final scaledR = (resonance / kMaxResonance) * kResonanceScale;

  // Φ_eff(t) = Φ(t) + R_scaled(t) ⋅ (1 + ∫ρΠ)
  final phiEff = phiRaw + scaledR * (1.0 + integral);
  return phiEff.clamp(0.0, 200.0);
}

// ─── SEMANTIC COMPRESSION ───────────────────────────────────────────────────
/// Message = ID + delta
/// Common phrases are mapped to short numeric codes.
/// A 100-char message "Hey, are you coming for dinner tonight?" → "07:19"
/// (code 07 = "are you coming for", code 19 = "dinner tonight")
class SemanticCompressor {
  /// Built during Home Charging Ritual
  final Map<String, String> _dictionary = {};
  int _nextCode = 0;

  /// Build dictionary from recent chat history
  void buildFromHistory(List<String> recentMessages) {
    // Extract common n-grams (bigrams and trigrams)
    final freq = <String, int>{};
    for (final msg in recentMessages) {
      final words = msg.toLowerCase().split(RegExp(r'\s+'));
      for (int n = 2; n <= 4; n++) {
        for (int i = 0; i <= words.length - n; i++) {
          final gram = words.sublist(i, i + n).join(' ');
          freq[gram] = (freq[gram] ?? 0) + 1;
        }
      }
    }
    // Keep phrases that appear ≥ 2 times
    final sorted = freq.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    _dictionary.clear();
    _nextCode = 0;
    for (final entry in sorted.take(200)) {
      final code = _nextCode.toRadixString(36).padLeft(2, '0');
      _dictionary[entry.key] = code;
      _nextCode++;
    }

    // Add common standalone phrases
    _addDefaults();
  }

  void _addDefaults() {
    final defaults = [
      'hello', 'hi', 'hey', 'good morning', 'good night', 'thanks',
      'thank you', 'yes', 'no', 'okay', 'ok', 'sure', 'see you',
      'bye', 'love you', 'miss you', 'on my way', 'be there soon',
      'what time', 'where are you', 'how are you', 'i am fine',
      'call me', 'can you', 'please', 'sorry', 'no problem',
      'good afternoon', 'good evening', 'take care', 'see you later',
      'i will be late', 'wait for me', 'coming soon', 'are you free',
      'let me know', 'sounds good', 'talk later', 'miss you too',
    ];
    for (final phrase in defaults) {
      if (!_dictionary.containsKey(phrase)) {
        final code = _nextCode.toRadixString(36).padLeft(2, '0');
        _dictionary[phrase] = code;
        _nextCode++;
      }
    }
  }

  /// Compress a message: replace known phrases with codes
  /// Returns (compressedPayload, compressionRatio)
  (String, double) compress(String message) {
    var result = message.toLowerCase();
    int originalLen = result.length;
    // Replace longest matches first
    final sortedPhrases = _dictionary.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final phrase in sortedPhrases) {
      result = result.replaceAll(phrase, '«${_dictionary[phrase]}»');
    }
    double ratio = result.length > 0
        ? (1.0 - result.length / originalLen).clamp(0.0, 1.0)
        : 0.0;
    return (result, ratio);
  }

  /// Decompress
  String decompress(String compressed) {
    var result = compressed;
    final reverseDict = _dictionary.map((k, v) => MapEntry(v, k));
    for (final entry in reverseDict.entries) {
      result = result.replaceAll('«${entry.key}»', entry.value);
    }
    return result;
  }

  int get dictionarySize => _dictionary.length;
  Map<String, String> get dictionary => Map.unmodifiable(_dictionary);
}

// ─── PRIORITY QUEUE ─────────────────────────────────────────────────────────
/// Messages are queued with priority. Higher priority → sent first when
/// connection pulse is detected.
enum MessagePriority {
  critical(4),   // Emergency / time-sensitive
  high(3),       // Direct replies
  normal(2),     // Standard messages
  low(1);        // Status updates, reactions

  final int weight;
  const MessagePriority(this.weight);
}

class PrioritizedMessage {
  final String id;
  final String content;
  final String compressedContent;
  final double compressionRatio;
  final MessagePriority priority;
  final DateTime createdAt;
  bool synced;

  PrioritizedMessage({
    required this.id,
    required this.content,
    required this.compressedContent,
    required this.compressionRatio,
    required this.priority,
    required this.createdAt,
    this.synced = false,
  });

  /// Priority score includes time-decay boost for older messages
  double get effectivePriority {
    final ageMinutes = DateTime.now().difference(createdAt).inMinutes;
    // Older messages get a slight boost to avoid starvation
    return priority.weight + (ageMinutes * 0.1).clamp(0.0, 2.0);
  }
}

// ─── PREDICTIVE SHADOW / DIGITAL TWIN ───────────────────────────────────────
/// Simulates predicted replies from the other user when they are offline.
/// Uses simple pattern matching on recent conversation context.
class DigitalTwin {
  final List<String> _recentContext = [];
  final _rng = Random();

  /// Feed recent messages for context
  void feedContext(List<String> messages) {
    _recentContext.clear();
    _recentContext.addAll(messages.take(50));
  }

  /// Generate a predicted reply (digital twin simulation)
  /// Returns null if confidence is too low
  String? predictReply(String lastMessage) {
    final lower = lastMessage.toLowerCase().trim();

    // Greeting patterns
    if (_matchesAny(lower, ['hello', 'hi', 'hey', 'good morning', 'good evening'])) {
      return _pick(['Hey! 👋', 'Hi there!', 'Hello!', 'Hey, what\'s up?']);
    }
    // Question patterns
    if (lower.contains('how are you') || lower.contains('how r u')) {
      return _pick(['I\'m good, thanks!', 'Doing well! You?', 'Great, wbu?']);
    }
    if (lower.contains('where are you') || lower.contains('where r u')) {
      return _pick(['On my way!', 'Almost there', 'Be there soon!']);
    }
    if (lower.contains('what time') || lower.contains('when')) {
      return _pick(['Let me check...', 'Give me a sec', 'Not sure yet']);
    }
    // Affirmation
    if (_matchesAny(lower, ['ok', 'okay', 'sure', 'yes', 'alright'])) {
      return _pick(['👍', 'Great!', 'Sounds good!', 'Perfect']);
    }
    // Farewell
    if (_matchesAny(lower, ['bye', 'see you', 'good night', 'gtg'])) {
      return _pick(['See you! 👋', 'Bye!', 'Take care!', 'Good night! 🌙']);
    }
    // Love
    if (lower.contains('love you') || lower.contains('miss you')) {
      return _pick(['❤️', 'Love you too!', 'Miss you too! 💕']);
    }
    // Thank
    if (lower.contains('thank') || lower.contains('thx')) {
      return _pick(['You\'re welcome!', 'No problem!', 'Anytime! 😊']);
    }
    // Default: low confidence → return null
    if (_rng.nextDouble() < 0.3) {
      return _pick(['Got it', '👍', 'Okay', 'Hmm', '...']);
    }
    return null;
  }

  bool _matchesAny(String text, List<String> patterns) {
    return patterns.any((p) => text.contains(p));
  }

  String _pick(List<String> options) {
    return options[_rng.nextInt(options.length)];
  }
}

// ─── THE MAIN ENGINE ────────────────────────────────────────────────────────
/// ConnectivityBatteryEngine drives the entire math model.
/// It ticks every 2 seconds, computes all equations, and notifies listeners.
///
/// IMPORTANT:
/// The engine now tracks message sync state authoritatively via
/// `markMessageSynced(id)` and `unsyncedMessageIds`. The chat screen
/// should call these instead of maintaining a separate sync-state list.
class ConnectivityBatteryEngine extends ChangeNotifier {
  // ── State ──
  EOCParams eocParams = EOCParams();
  MBatteryParams mParams = MBatteryParams();
  final SemanticCompressor compressor = SemanticCompressor();
  final DigitalTwin digitalTwin = DigitalTwin();

  // ── Current values ──
  double _currentEOC = 0.0;
  double _currentM = 0.0;
  double _currentPhiEff = 0.0;
  double _currentResonance = 0.0;
  bool _isOnline = true;
  bool _isCharged = false;
  DateTime _lastOnlineTime = DateTime.now();

  // ── Resonance integral samples: ρ(s)⋅Π(s) ──
  final List<double> _rhoPiSamples = [];

  /// ── Π(s) priority accumulator ──
  /// Every time a message is sent, the priority weight for the NEXT sample
  /// is boosted. This makes the integral capture "user intent" — sending
  /// messages while offline amplifies the resonance field.
  double _pendingPriorityBoost = 0.0;

  // ── History for graph ──
  final List<BatterySnapshot> _history = [];

  // ── Queued messages ──
  final List<PrioritizedMessage> _messageQueue = [];

  // ── Timer ──
  Timer? _ticker;



  // ── Getters ──
  double get currentEOC => _currentEOC;
  double get currentM => _currentM;
  double get currentPhiEff => _currentPhiEff;
  double get currentResonance => _currentResonance;
  double get reservePercent => (_currentPhiEff / 200.0 * 100.0).clamp(0.0, 100.0);
  bool get isOnline => _isOnline;
  bool get isForceOffline => false; // legacy — always false now
  bool get isCharged => _isCharged;
  List<BatterySnapshot> get history => List.unmodifiable(_history);
  List<PrioritizedMessage> get messageQueue => List.unmodifiable(_messageQueue);
  int get queuedCount => _messageQueue.where((m) => !m.synced).length;

  /// IDs of messages that haven't been synced to Firestore yet.
  /// The chat screen uses this to know what to push on reconnect.
  Set<String> get unsyncedMessageIds =>
      _messageQueue.where((m) => !m.synced).map((m) => m.id).toSet();

  /// Start the engine tick
  void startEngine() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    _tick(); // initial
  }

  /// Stop engine
  void stopEngine() {
    _ticker?.cancel();
  }

  /// Triggered when WiFi / data connectivity changes
  void updateConnectivity(bool online) {
    final wasOffline = !_isOnline;
    _isOnline = online;
    if (online && wasOffline) {
      // Connection pulse detected! Boost resonance
      _onConnectionPulse();
    }
    if (!online) {
      _lastOnlineTime = DateTime.now();
    }
    _tick();
  }

  /// Legacy — kept for API compatibility but does nothing.
  /// Real offline is detected via ConnectivityService.
  void setForceOffline(bool force) {}

  /// Perform the Home Charging Ritual
  void performChargingRitual({
    required List<String> recentMessages,
    int preSignedEnvelopes = 25,
  }) {
    // Build semantic dictionary
    compressor.buildFromHistory(recentMessages);

    // Feed digital twin with context
    digitalTwin.feedContext(recentMessages);

    // Reset battery to full
    mParams = MBatteryParams(
      semanticReservoir: 40.0 + compressor.dictionarySize * 0.05,
      keyEnvelopeStock: preSignedEnvelopes.toDouble(),
      queueDepthReserve: 35.0,
      resonanceCharge: 50.0,
      decay: 0.0,
      loss: 0.0,
    );

    // Reset resonance to full
    _currentResonance = kMaxResonance; // 120 presence-joules

    // Reset EOC to optimal
    eocParams = EOCParams(
      cachedContent: 0.95,
      trustToken: 1.0,
      presence: 0.9,
      friendshipBond: 0.8,
      disconnectDur: 0.0,
      uncertainty: 0.05,
    );

    // Clear integral samples, start fresh
    _rhoPiSamples.clear();
    _rhoPiSamples.add(1.0); // initial ρ⋅Π = 1.0 at full charge
    _pendingPriorityBoost = 0.0;

    // Mark charged
    _isCharged = true;

    // Clear history
    _history.clear();

    _tick();
    notifyListeners();
  }

  /// Queue a message for sending.
  /// If the engine is effectively online, mark synced immediately.
  PrioritizedMessage queueMessage({
    required String id,
    required String content,
    MessagePriority priority = MessagePriority.normal,
  }) {
    // Semantic compression
    final (compressed, ratio) = compressor.compress(content);

    final effectiveOnline = _isOnline;

    final msg = PrioritizedMessage(
      id: id,
      content: content,
      compressedContent: compressed,
      compressionRatio: ratio,
      priority: priority,
      createdAt: DateTime.now(),
      synced: effectiveOnline, // pre-mark synced if online
    );

    _messageQueue.add(msg);

    // Consume battery: each message costs some from semantic reservoir + envelope
    mParams.semanticReservoir = (mParams.semanticReservoir - 1.0).clamp(0.0, 100.0);
    mParams.keyEnvelopeStock = (mParams.keyEnvelopeStock - 0.5).clamp(0.0, 100.0);

    // Boost Π(s) — user intent during offline amplifies the resonance field
    if (!effectiveOnline) {
      _pendingPriorityBoost += priority.weight * 0.15;
      // Offline messages also increase the loss counter slightly
      // (they risk being lost until synced)
      mParams.loss = (mParams.loss + 0.3).clamp(0.0, 100.0);
    }

    _tick();
    notifyListeners();
    return msg;
  }

  /// Mark a specific message as synced by ID.
  /// Called by the chat screen when Firebase confirms the write.
  void markMessageSynced(String messageId) {
    final idx = _messageQueue.indexWhere((m) => m.id == messageId);
    if (idx >= 0 && !_messageQueue[idx].synced) {
      _messageQueue[idx].synced = true;
      // Reduce loss — successful delivery
      mParams.loss = (mParams.loss - 0.3).clamp(0.0, 100.0);
    }
  }

  /// Mark all unsynced messages as synced (batch sync completed).
  int syncAllMessages() {
    int synced = 0;
    // Sort by priority — highest priority first
    final pending = _messageQueue.where((m) => !m.synced).toList()
      ..sort((a, b) => b.effectivePriority.compareTo(a.effectivePriority));
    for (final msg in pending) {
      msg.synced = true;
      synced++;
    }
    // Reduce loss counter on successful sync
    mParams.loss = (mParams.loss - synced * 0.3).clamp(0.0, 100.0);
    _tick();
    notifyListeners();
    return synced;
  }

  /// Connection pulse detected — boost resonance field
  void _onConnectionPulse() {
    _currentResonance = (_currentResonance + kResonancePulseBoost)
        .clamp(0.0, kMaxResonance);
    // Add a high ρ⋅Π sample — pulse is a burst of connectivity
    _rhoPiSamples.add(0.8 + Random().nextDouble() * 0.2);

    // Reduce disconnect duration
    eocParams.disconnectDur = 0.0;
    eocParams.uncertainty = (eocParams.uncertainty - 0.05).clamp(0.0, 1.0);
  }

  /// Main tick — recompute all equations
  void _tick() {
    final effectiveOnline = _isOnline;

    // ── Update disconnect duration ──
    if (!effectiveOnline) {
      final offlineMinutes = DateTime.now()
          .difference(_lastOnlineTime)
          .inSeconds / 60.0;
      eocParams.disconnectDur = offlineMinutes;
      eocParams.uncertainty = (0.05 + offlineMinutes * 0.01).clamp(0.0, 1.0);

      // Decay battery
      mParams.decay += kDecayPerMinute / 30.0; // every 2-second tick

      // Passive resonance decay
      _currentResonance = (_currentResonance - kResonancePassiveDecay / 30.0)
          .clamp(0.0, kMaxResonance);

      // Presence slowly drops
      eocParams.presence = (eocParams.presence - 0.001).clamp(0.0, 1.0);
    } else {
      // Online: slowly recharge
      eocParams.disconnectDur = 0.0;
      eocParams.uncertainty = (eocParams.uncertainty - 0.005).clamp(0.0, 1.0);
      eocParams.presence = (eocParams.presence + 0.002).clamp(0.0, 1.0);
      _currentResonance = (_currentResonance + 0.05).clamp(0.0, kMaxResonance);
    }

    // ── Compute EOC ──
    _currentEOC = computeEOC(eocParams);

    // ── Compute M(t) ──
    mParams.resonanceCharge = _currentResonance / kMaxResonance * 50.0;
    _currentM = computeM(mParams);

    // ── Compute Φ_eff(t) using Resonance Continuity Axiom ──
    //
    // Build the ρ(s)⋅Π(s) sample for this tick:
    //   ρ(s) = EOC(s) × connectivity_factor
    //     Online:  connectivity_factor = 1.0
    //     Offline: connectivity_factor = 0.3  (residual field from cache)
    //   Π(s) = base_priority + pending_boost
    //     base_priority = 1.0
    //     pending_boost = accumulated from recent message sends
    //
    // This means: sending messages while offline actually BOOSTS the
    // integral, making Φ_eff higher — the act of communicating strengthens
    // the resonance field. This is the "perceived continuity" effect.
    final rho = _currentEOC * (effectiveOnline ? 1.0 : 0.3);
    final pi = 1.0 + _pendingPriorityBoost;
    final rhoPi = rho * pi;

    // Decay the priority boost gradually so it doesn't stick forever
    _pendingPriorityBoost *= 0.95;
    if (_pendingPriorityBoost < 0.001) _pendingPriorityBoost = 0.0;

    _rhoPiSamples.add(rhoPi);
    // Keep only last 300 samples (10 minutes at 2s intervals)
    if (_rhoPiSamples.length > 300) {
      _rhoPiSamples.removeAt(0);
    }

    _currentPhiEff = computePhiEff(
      phiRaw: _currentEOC * 100.0,        // scale EOC [0..1] → [0..100]
      resonance: _currentResonance,         // pass raw R(t), scaling is in computePhiEff
      rhoPi: _rhoPiSamples,
      dt: 2.0 / 60.0,                     // 2 seconds → minutes
    );

    // ── Record snapshot ──
    _history.add(BatterySnapshot(
      time: DateTime.now(),
      phiEff: _currentPhiEff,
      mBattery: _currentM,
      resonance: _currentResonance,
      eoc: _currentEOC,
    ));
    // Keep last 600 snapshots (20 minutes)
    if (_history.length > 600) {
      _history.removeAt(0);
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
