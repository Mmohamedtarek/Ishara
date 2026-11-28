import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';

/// The synced collections (Phase 0 model; never conversations, emergency
/// contacts, the paired glove or anything from SOS, Q-B4).
abstract final class Synced {
  static const settings = 'settings';
  static const phrases = 'phrases';
  static const activity = 'activity';

  /// The one settings document.
  static const settingsDoc = 'app';

  /// The longest phrase the account takes: `isText(data().text, 500)` in
  /// `firebase/firestore.rules`, which counts UTF-16 units like
  /// [String.length] (measured in the emulator: 500 Arabic letters, 250
  /// emoji; `firebase/test/rules.test.js`).
  static const phraseMaxLength = 500;

  /// Whether a phrase with [text] syncs. Longer ones can still be starred:
  /// they stay on this phone only, are never queued, and so never count as
  /// "not uploaded" at sign-out (user 2026-11-27).
  static bool phraseFits(String text) => text.length <= phraseMaxLength;
}

/// Queues the document [collection]/[docId] for the sync (one row per
/// document; its newest local state is read when it is sent). Call inside
/// the transaction that changes the row, so both are stored or neither.
Future<void> enqueue(AppDatabase db, String collection, String docId) => db
    .into(db.outbox)
    .insertOnConflictUpdate(
      OutboxCompanion.insert(
        collection: collection,
        docId: docId,
        queuedAtUs: clock.now().microsecondsSinceEpoch,
        attempts: const Value(0),
        nextAttemptUs: const Value(0),
        lastError: const Value(null),
      ),
    );
