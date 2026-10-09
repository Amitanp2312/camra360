import 'package:drift/drift.dart';

part 'app_database.g.dart';

const uploadJobPending = 'pending';
const uploadJobAbandoned = 'abandoned';

/// One JPEG waiting to be uploaded and inserted as a captures row.
@DataClassName('UploadJob')
class UploadJobs extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get sessionId => text()();
  TextColumn get localPath => text()();
  RealColumn get yaw => real()();
  RealColumn get pitch => real()();
  RealColumn get roll => real().nullable()();
  RealColumn get fov => real().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime()();
  TextColumn get lastError => text().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant(uploadJobPending))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [UploadJobs])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  Future<void> enqueueJob(UploadJobsCompanion job) {
    return into(uploadJobs).insert(job);
  }

  Future<UploadJob?> nextDue(DateTime now) {
    return (select(uploadJobs)
          ..where(
            (row) =>
                row.status.equals(uploadJobPending) &
                row.nextAttemptAt.isSmallerOrEqualValue(now),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.nextAttemptAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<DateTime?> earliestPendingAttempt() async {
    final row =
        await (select(uploadJobs)
              ..where((row) => row.status.equals(uploadJobPending))
              ..orderBy([(row) => OrderingTerm.asc(row.nextAttemptAt)])
              ..limit(1))
            .getSingleOrNull();
    return row?.nextAttemptAt;
  }

  Future<void> markAttempt({
    required String id,
    required int attempts,
    required DateTime nextAttemptAt,
  }) {
    return (update(uploadJobs)..where((row) => row.id.equals(id))).write(
      UploadJobsCompanion(
        attempts: Value(attempts),
        nextAttemptAt: Value(nextAttemptAt),
      ),
    );
  }

  Future<void> setError(String id, String message) {
    return (update(uploadJobs)..where((row) => row.id.equals(id))).write(
      UploadJobsCompanion(lastError: Value(message)),
    );
  }

  Future<void> abandon(String id, String message) {
    return (update(uploadJobs)..where((row) => row.id.equals(id))).write(
      UploadJobsCompanion(
        status: const Value(uploadJobAbandoned),
        lastError: Value(message),
      ),
    );
  }

  Future<void> deleteJob(String id) {
    return (delete(uploadJobs)..where((row) => row.id.equals(id))).go();
  }

  Future<UploadJob?> jobById(String id) {
    return (select(uploadJobs)..where((row) => row.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<UploadJob>> jobsForSession(String sessionId) {
    return (select(uploadJobs)
          ..where((row) => row.sessionId.equals(sessionId)))
        .get();
  }

  Future<List<UploadJob>> allJobs() {
    return select(uploadJobs).get();
  }

  Future<void> deleteAllJobs() {
    return delete(uploadJobs).go();
  }

  Stream<List<UploadJob>> watchPending() {
    return (select(uploadJobs)
          ..where((row) => row.status.equals(uploadJobPending))
          ..orderBy([(row) => OrderingTerm.asc(row.nextAttemptAt)]))
        .watch();
  }

  /// Pending jobs should run on the next pass instead of waiting out a backoff.
  Future<void> releaseBackoff(DateTime now) {
    return (update(uploadJobs)
          ..where((row) => row.status.equals(uploadJobPending)))
        .write(UploadJobsCompanion(nextAttemptAt: Value(now)));
  }
}
