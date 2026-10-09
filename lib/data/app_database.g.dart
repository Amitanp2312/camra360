// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $UploadJobsTable extends UploadJobs
    with TableInfo<$UploadJobsTable, UploadJob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yawMeta = const VerificationMeta('yaw');
  @override
  late final GeneratedColumn<double> yaw = GeneratedColumn<double>(
    'yaw',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pitchMeta = const VerificationMeta('pitch');
  @override
  late final GeneratedColumn<double> pitch = GeneratedColumn<double>(
    'pitch',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rollMeta = const VerificationMeta('roll');
  @override
  late final GeneratedColumn<double> roll = GeneratedColumn<double>(
    'roll',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fovMeta = const VerificationMeta('fov');
  @override
  late final GeneratedColumn<double> fov = GeneratedColumn<double>(
    'fov',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(uploadJobPending),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    sessionId,
    localPath,
    yaw,
    pitch,
    roll,
    fov,
    width,
    height,
    attempts,
    nextAttemptAt,
    lastError,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'upload_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<UploadJob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('yaw')) {
      context.handle(
        _yawMeta,
        yaw.isAcceptableOrUnknown(data['yaw']!, _yawMeta),
      );
    } else if (isInserting) {
      context.missing(_yawMeta);
    }
    if (data.containsKey('pitch')) {
      context.handle(
        _pitchMeta,
        pitch.isAcceptableOrUnknown(data['pitch']!, _pitchMeta),
      );
    } else if (isInserting) {
      context.missing(_pitchMeta);
    }
    if (data.containsKey('roll')) {
      context.handle(
        _rollMeta,
        roll.isAcceptableOrUnknown(data['roll']!, _rollMeta),
      );
    }
    if (data.containsKey('fov')) {
      context.handle(
        _fovMeta,
        fov.isAcceptableOrUnknown(data['fov']!, _fovMeta),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nextAttemptAtMeta);
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UploadJob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UploadJob(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      yaw: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}yaw'],
      )!,
      pitch: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pitch'],
      )!,
      roll: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}roll'],
      ),
      fov: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fov'],
      ),
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $UploadJobsTable createAlias(String alias) {
    return $UploadJobsTable(attachedDatabase, alias);
  }
}

class UploadJob extends DataClass implements Insertable<UploadJob> {
  final String id;
  final String userId;
  final String sessionId;
  final String localPath;
  final double yaw;
  final double pitch;
  final double? roll;
  final double? fov;
  final int? width;
  final int? height;
  final int attempts;
  final DateTime nextAttemptAt;
  final String? lastError;
  final String status;
  const UploadJob({
    required this.id,
    required this.userId,
    required this.sessionId,
    required this.localPath,
    required this.yaw,
    required this.pitch,
    this.roll,
    this.fov,
    this.width,
    this.height,
    required this.attempts,
    required this.nextAttemptAt,
    this.lastError,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['session_id'] = Variable<String>(sessionId);
    map['local_path'] = Variable<String>(localPath);
    map['yaw'] = Variable<double>(yaw);
    map['pitch'] = Variable<double>(pitch);
    if (!nullToAbsent || roll != null) {
      map['roll'] = Variable<double>(roll);
    }
    if (!nullToAbsent || fov != null) {
      map['fov'] = Variable<double>(fov);
    }
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    map['attempts'] = Variable<int>(attempts);
    map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['status'] = Variable<String>(status);
    return map;
  }

  UploadJobsCompanion toCompanion(bool nullToAbsent) {
    return UploadJobsCompanion(
      id: Value(id),
      userId: Value(userId),
      sessionId: Value(sessionId),
      localPath: Value(localPath),
      yaw: Value(yaw),
      pitch: Value(pitch),
      roll: roll == null && nullToAbsent ? const Value.absent() : Value(roll),
      fov: fov == null && nullToAbsent ? const Value.absent() : Value(fov),
      width: width == null && nullToAbsent
          ? const Value.absent()
          : Value(width),
      height: height == null && nullToAbsent
          ? const Value.absent()
          : Value(height),
      attempts: Value(attempts),
      nextAttemptAt: Value(nextAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      status: Value(status),
    );
  }

  factory UploadJob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UploadJob(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      localPath: serializer.fromJson<String>(json['localPath']),
      yaw: serializer.fromJson<double>(json['yaw']),
      pitch: serializer.fromJson<double>(json['pitch']),
      roll: serializer.fromJson<double?>(json['roll']),
      fov: serializer.fromJson<double?>(json['fov']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime>(json['nextAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'sessionId': serializer.toJson<String>(sessionId),
      'localPath': serializer.toJson<String>(localPath),
      'yaw': serializer.toJson<double>(yaw),
      'pitch': serializer.toJson<double>(pitch),
      'roll': serializer.toJson<double?>(roll),
      'fov': serializer.toJson<double?>(fov),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime>(nextAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
      'status': serializer.toJson<String>(status),
    };
  }

  UploadJob copyWith({
    String? id,
    String? userId,
    String? sessionId,
    String? localPath,
    double? yaw,
    double? pitch,
    Value<double?> roll = const Value.absent(),
    Value<double?> fov = const Value.absent(),
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    int? attempts,
    DateTime? nextAttemptAt,
    Value<String?> lastError = const Value.absent(),
    String? status,
  }) => UploadJob(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    sessionId: sessionId ?? this.sessionId,
    localPath: localPath ?? this.localPath,
    yaw: yaw ?? this.yaw,
    pitch: pitch ?? this.pitch,
    roll: roll.present ? roll.value : this.roll,
    fov: fov.present ? fov.value : this.fov,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    status: status ?? this.status,
  );
  UploadJob copyWithCompanion(UploadJobsCompanion data) {
    return UploadJob(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      yaw: data.yaw.present ? data.yaw.value : this.yaw,
      pitch: data.pitch.present ? data.pitch.value : this.pitch,
      roll: data.roll.present ? data.roll.value : this.roll,
      fov: data.fov.present ? data.fov.value : this.fov,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UploadJob(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('sessionId: $sessionId, ')
          ..write('localPath: $localPath, ')
          ..write('yaw: $yaw, ')
          ..write('pitch: $pitch, ')
          ..write('roll: $roll, ')
          ..write('fov: $fov, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    sessionId,
    localPath,
    yaw,
    pitch,
    roll,
    fov,
    width,
    height,
    attempts,
    nextAttemptAt,
    lastError,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadJob &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.sessionId == this.sessionId &&
          other.localPath == this.localPath &&
          other.yaw == this.yaw &&
          other.pitch == this.pitch &&
          other.roll == this.roll &&
          other.fov == this.fov &&
          other.width == this.width &&
          other.height == this.height &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastError == this.lastError &&
          other.status == this.status);
}

class UploadJobsCompanion extends UpdateCompanion<UploadJob> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> sessionId;
  final Value<String> localPath;
  final Value<double> yaw;
  final Value<double> pitch;
  final Value<double?> roll;
  final Value<double?> fov;
  final Value<int?> width;
  final Value<int?> height;
  final Value<int> attempts;
  final Value<DateTime> nextAttemptAt;
  final Value<String?> lastError;
  final Value<String> status;
  final Value<int> rowid;
  const UploadJobsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.localPath = const Value.absent(),
    this.yaw = const Value.absent(),
    this.pitch = const Value.absent(),
    this.roll = const Value.absent(),
    this.fov = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UploadJobsCompanion.insert({
    required String id,
    required String userId,
    required String sessionId,
    required String localPath,
    required double yaw,
    required double pitch,
    this.roll = const Value.absent(),
    this.fov = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.attempts = const Value.absent(),
    required DateTime nextAttemptAt,
    this.lastError = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       sessionId = Value(sessionId),
       localPath = Value(localPath),
       yaw = Value(yaw),
       pitch = Value(pitch),
       nextAttemptAt = Value(nextAttemptAt);
  static Insertable<UploadJob> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? sessionId,
    Expression<String>? localPath,
    Expression<double>? yaw,
    Expression<double>? pitch,
    Expression<double>? roll,
    Expression<double>? fov,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? attempts,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastError,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (sessionId != null) 'session_id': sessionId,
      if (localPath != null) 'local_path': localPath,
      if (yaw != null) 'yaw': yaw,
      if (pitch != null) 'pitch': pitch,
      if (roll != null) 'roll': roll,
      if (fov != null) 'fov': fov,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UploadJobsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? sessionId,
    Value<String>? localPath,
    Value<double>? yaw,
    Value<double>? pitch,
    Value<double?>? roll,
    Value<double?>? fov,
    Value<int?>? width,
    Value<int?>? height,
    Value<int>? attempts,
    Value<DateTime>? nextAttemptAt,
    Value<String?>? lastError,
    Value<String>? status,
    Value<int>? rowid,
  }) {
    return UploadJobsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      sessionId: sessionId ?? this.sessionId,
      localPath: localPath ?? this.localPath,
      yaw: yaw ?? this.yaw,
      pitch: pitch ?? this.pitch,
      roll: roll ?? this.roll,
      fov: fov ?? this.fov,
      width: width ?? this.width,
      height: height ?? this.height,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (yaw.present) {
      map['yaw'] = Variable<double>(yaw.value);
    }
    if (pitch.present) {
      map['pitch'] = Variable<double>(pitch.value);
    }
    if (roll.present) {
      map['roll'] = Variable<double>(roll.value);
    }
    if (fov.present) {
      map['fov'] = Variable<double>(fov.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadJobsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('sessionId: $sessionId, ')
          ..write('localPath: $localPath, ')
          ..write('yaw: $yaw, ')
          ..write('pitch: $pitch, ')
          ..write('roll: $roll, ')
          ..write('fov: $fov, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $UploadJobsTable uploadJobs = $UploadJobsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [uploadJobs];
}

typedef $$UploadJobsTableCreateCompanionBuilder = UploadJobsCompanion Function({
  required String id,
  required String userId,
  required String sessionId,
  required String localPath,
  required double yaw,
  required double pitch,
  Value<double?> roll,
  Value<double?> fov,
  Value<int?> width,
  Value<int?> height,
  Value<int> attempts,
  required DateTime nextAttemptAt,
  Value<String?> lastError,
  Value<String> status,
  Value<int> rowid,
});
typedef $$UploadJobsTableUpdateCompanionBuilder = UploadJobsCompanion Function({
  Value<String> id,
  Value<String> userId,
  Value<String> sessionId,
  Value<String> localPath,
  Value<double> yaw,
  Value<double> pitch,
  Value<double?> roll,
  Value<double?> fov,
  Value<int?> width,
  Value<int?> height,
  Value<int> attempts,
  Value<DateTime> nextAttemptAt,
  Value<String?> lastError,
  Value<String> status,
  Value<int> rowid,
});

class $$UploadJobsTableFilterComposer
    extends Composer<_$AppDatabase, $UploadJobsTable> {
  $$UploadJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get yaw => $composableBuilder(
    column: $table.yaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pitch => $composableBuilder(
    column: $table.pitch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get roll => $composableBuilder(
    column: $table.roll,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fov => $composableBuilder(
    column: $table.fov,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UploadJobsTableOrderingComposer
    extends Composer<_$AppDatabase, $UploadJobsTable> {
  $$UploadJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get yaw => $composableBuilder(
    column: $table.yaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pitch => $composableBuilder(
    column: $table.pitch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get roll => $composableBuilder(
    column: $table.roll,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fov => $composableBuilder(
    column: $table.fov,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UploadJobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UploadJobsTable> {
  $$UploadJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<double> get yaw =>
      $composableBuilder(column: $table.yaw, builder: (column) => column);

  GeneratedColumn<double> get pitch =>
      $composableBuilder(column: $table.pitch, builder: (column) => column);

  GeneratedColumn<double> get roll =>
      $composableBuilder(column: $table.roll, builder: (column) => column);

  GeneratedColumn<double> get fov =>
      $composableBuilder(column: $table.fov, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$UploadJobsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UploadJobsTable,
          UploadJob,
          $$UploadJobsTableFilterComposer,
          $$UploadJobsTableOrderingComposer,
          $$UploadJobsTableAnnotationComposer,
          $$UploadJobsTableCreateCompanionBuilder,
          $$UploadJobsTableUpdateCompanionBuilder,
          (
            UploadJob,
            BaseReferences<_$AppDatabase, $UploadJobsTable, UploadJob>,
          ),
          UploadJob,
          PrefetchHooks Function()
        > {
  $$UploadJobsTableTableManager(_$AppDatabase db, $UploadJobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UploadJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<double> yaw = const Value.absent(),
                Value<double> pitch = const Value.absent(),
                Value<double?> roll = const Value.absent(),
                Value<double?> fov = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadJobsCompanion(
                id: id,
                userId: userId,
                sessionId: sessionId,
                localPath: localPath,
                yaw: yaw,
                pitch: pitch,
                roll: roll,
                fov: fov,
                width: width,
                height: height,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                status: status,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String sessionId,
                required String localPath,
                required double yaw,
                required double pitch,
                Value<double?> roll = const Value.absent(),
                Value<double?> fov = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                required DateTime nextAttemptAt,
                Value<String?> lastError = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadJobsCompanion.insert(
                id: id,
                userId: userId,
                sessionId: sessionId,
                localPath: localPath,
                yaw: yaw,
                pitch: pitch,
                roll: roll,
                fov: fov,
                width: width,
                height: height,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                status: status,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UploadJobsTable, UploadJob>(table),
                  BaseReferences<_$AppDatabase, $UploadJobsTable, UploadJob>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UploadJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UploadJobsTable,
      UploadJob,
      $$UploadJobsTableFilterComposer,
      $$UploadJobsTableOrderingComposer,
      $$UploadJobsTableAnnotationComposer,
      $$UploadJobsTableCreateCompanionBuilder,
      $$UploadJobsTableUpdateCompanionBuilder,
      (UploadJob, BaseReferences<_$AppDatabase, $UploadJobsTable, UploadJob>),
      UploadJob,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$UploadJobsTableTableManager get uploadJobs =>
      $$UploadJobsTableTableManager(_db, _db.uploadJobs);
}
