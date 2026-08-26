// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PresetsTable extends Presets with TableInfo<$PresetsTable, PresetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PresetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _traditionMeta = const VerificationMeta(
    'tradition',
  );
  @override
  late final GeneratedColumn<String> tradition = GeneratedColumn<String>(
    'tradition',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, version, tradition, data];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'presets';
  @override
  VerificationContext validateIntegrity(
    Insertable<PresetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('tradition')) {
      context.handle(
        _traditionMeta,
        tradition.isAcceptableOrUnknown(data['tradition']!, _traditionMeta),
      );
    } else if (isInserting) {
      context.missing(_traditionMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PresetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PresetRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      tradition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tradition'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
    );
  }

  @override
  $PresetsTable createAlias(String alias) {
    return $PresetsTable(attachedDatabase, alias);
  }
}

class PresetsCompanion extends UpdateCompanion<PresetRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> version;
  final Value<String> tradition;
  final Value<String> data;
  final Value<int> rowid;
  const PresetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.version = const Value.absent(),
    this.tradition = const Value.absent(),
    this.data = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PresetsCompanion.insert({
    required String id,
    required String name,
    required String version,
    required String tradition,
    required String data,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       version = Value(version),
       tradition = Value(tradition),
       data = Value(data);
  static Insertable<PresetRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? version,
    Expression<String>? tradition,
    Expression<String>? data,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (version != null) 'version': version,
      if (tradition != null) 'tradition': tradition,
      if (data != null) 'data': data,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PresetsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? version,
    Value<String>? tradition,
    Value<String>? data,
    Value<int>? rowid,
  }) {
    return PresetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      tradition: tradition ?? this.tradition,
      data: data ?? this.data,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (tradition.present) {
      map['tradition'] = Variable<String>(tradition.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PresetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('version: $version, ')
          ..write('tradition: $tradition, ')
          ..write('data: $data, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PracticesTable extends Practices
    with TableInfo<$PracticesTable, Practice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PracticesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _presetIdMeta = const VerificationMeta(
    'presetId',
  );
  @override
  late final GeneratedColumn<String> presetId = GeneratedColumn<String>(
    'preset_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetMeta = const VerificationMeta('target');
  @override
  late final GeneratedColumn<int> target = GeneratedColumn<int>(
    'target',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _traditionTagMeta = const VerificationMeta(
    'traditionTag',
  );
  @override
  late final GeneratedColumn<String> traditionTag = GeneratedColumn<String>(
    'tradition_tag',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentCountMeta = const VerificationMeta(
    'currentCount',
  );
  @override
  late final GeneratedColumn<int> currentCount = GeneratedColumn<int>(
    'current_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    presetId,
    name,
    type,
    target,
    unit,
    traditionTag,
    currentCount,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'practices';
  @override
  VerificationContext validateIntegrity(
    Insertable<Practice> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('preset_id')) {
      context.handle(
        _presetIdMeta,
        presetId.isAcceptableOrUnknown(data['preset_id']!, _presetIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('target')) {
      context.handle(
        _targetMeta,
        target.isAcceptableOrUnknown(data['target']!, _targetMeta),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('tradition_tag')) {
      context.handle(
        _traditionTagMeta,
        traditionTag.isAcceptableOrUnknown(
          data['tradition_tag']!,
          _traditionTagMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_traditionTagMeta);
    }
    if (data.containsKey('current_count')) {
      context.handle(
        _currentCountMeta,
        currentCount.isAcceptableOrUnknown(
          data['current_count']!,
          _currentCountMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Practice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Practice(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      presetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preset_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      target: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target'],
      ),
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      ),
      traditionTag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tradition_tag'],
      )!,
      currentCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_count'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PracticesTable createAlias(String alias) {
    return $PracticesTable(attachedDatabase, alias);
  }
}

class Practice extends DataClass implements Insertable<Practice> {
  final int id;
  final String? presetId;
  final String name;
  final String type;
  final int? target;
  final String? unit;
  final String traditionTag;
  final int currentCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Practice({
    required this.id,
    this.presetId,
    required this.name,
    required this.type,
    this.target,
    this.unit,
    required this.traditionTag,
    required this.currentCount,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || presetId != null) {
      map['preset_id'] = Variable<String>(presetId);
    }
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || target != null) {
      map['target'] = Variable<int>(target);
    }
    if (!nullToAbsent || unit != null) {
      map['unit'] = Variable<String>(unit);
    }
    map['tradition_tag'] = Variable<String>(traditionTag);
    map['current_count'] = Variable<int>(currentCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PracticesCompanion toCompanion(bool nullToAbsent) {
    return PracticesCompanion(
      id: Value(id),
      presetId: presetId == null && nullToAbsent
          ? const Value.absent()
          : Value(presetId),
      name: Value(name),
      type: Value(type),
      target: target == null && nullToAbsent
          ? const Value.absent()
          : Value(target),
      unit: unit == null && nullToAbsent ? const Value.absent() : Value(unit),
      traditionTag: Value(traditionTag),
      currentCount: Value(currentCount),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Practice.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Practice(
      id: serializer.fromJson<int>(json['id']),
      presetId: serializer.fromJson<String?>(json['presetId']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      target: serializer.fromJson<int?>(json['target']),
      unit: serializer.fromJson<String?>(json['unit']),
      traditionTag: serializer.fromJson<String>(json['traditionTag']),
      currentCount: serializer.fromJson<int>(json['currentCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'presetId': serializer.toJson<String?>(presetId),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'target': serializer.toJson<int?>(target),
      'unit': serializer.toJson<String?>(unit),
      'traditionTag': serializer.toJson<String>(traditionTag),
      'currentCount': serializer.toJson<int>(currentCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Practice copyWith({
    int? id,
    Value<String?> presetId = const Value.absent(),
    String? name,
    String? type,
    Value<int?> target = const Value.absent(),
    Value<String?> unit = const Value.absent(),
    String? traditionTag,
    int? currentCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Practice(
    id: id ?? this.id,
    presetId: presetId.present ? presetId.value : this.presetId,
    name: name ?? this.name,
    type: type ?? this.type,
    target: target.present ? target.value : this.target,
    unit: unit.present ? unit.value : this.unit,
    traditionTag: traditionTag ?? this.traditionTag,
    currentCount: currentCount ?? this.currentCount,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Practice copyWithCompanion(PracticesCompanion data) {
    return Practice(
      id: data.id.present ? data.id.value : this.id,
      presetId: data.presetId.present ? data.presetId.value : this.presetId,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      target: data.target.present ? data.target.value : this.target,
      unit: data.unit.present ? data.unit.value : this.unit,
      traditionTag: data.traditionTag.present
          ? data.traditionTag.value
          : this.traditionTag,
      currentCount: data.currentCount.present
          ? data.currentCount.value
          : this.currentCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Practice(')
          ..write('id: $id, ')
          ..write('presetId: $presetId, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('target: $target, ')
          ..write('unit: $unit, ')
          ..write('traditionTag: $traditionTag, ')
          ..write('currentCount: $currentCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    presetId,
    name,
    type,
    target,
    unit,
    traditionTag,
    currentCount,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Practice &&
          other.id == this.id &&
          other.presetId == this.presetId &&
          other.name == this.name &&
          other.type == this.type &&
          other.target == this.target &&
          other.unit == this.unit &&
          other.traditionTag == this.traditionTag &&
          other.currentCount == this.currentCount &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PracticesCompanion extends UpdateCompanion<Practice> {
  final Value<int> id;
  final Value<String?> presetId;
  final Value<String> name;
  final Value<String> type;
  final Value<int?> target;
  final Value<String?> unit;
  final Value<String> traditionTag;
  final Value<int> currentCount;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const PracticesCompanion({
    this.id = const Value.absent(),
    this.presetId = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.target = const Value.absent(),
    this.unit = const Value.absent(),
    this.traditionTag = const Value.absent(),
    this.currentCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  PracticesCompanion.insert({
    this.id = const Value.absent(),
    this.presetId = const Value.absent(),
    required String name,
    required String type,
    this.target = const Value.absent(),
    this.unit = const Value.absent(),
    required String traditionTag,
    this.currentCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name),
       type = Value(type),
       traditionTag = Value(traditionTag);
  static Insertable<Practice> custom({
    Expression<int>? id,
    Expression<String>? presetId,
    Expression<String>? name,
    Expression<String>? type,
    Expression<int>? target,
    Expression<String>? unit,
    Expression<String>? traditionTag,
    Expression<int>? currentCount,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (presetId != null) 'preset_id': presetId,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (target != null) 'target': target,
      if (unit != null) 'unit': unit,
      if (traditionTag != null) 'tradition_tag': traditionTag,
      if (currentCount != null) 'current_count': currentCount,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  PracticesCompanion copyWith({
    Value<int>? id,
    Value<String?>? presetId,
    Value<String>? name,
    Value<String>? type,
    Value<int?>? target,
    Value<String?>? unit,
    Value<String>? traditionTag,
    Value<int>? currentCount,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return PracticesCompanion(
      id: id ?? this.id,
      presetId: presetId ?? this.presetId,
      name: name ?? this.name,
      type: type ?? this.type,
      target: target ?? this.target,
      unit: unit ?? this.unit,
      traditionTag: traditionTag ?? this.traditionTag,
      currentCount: currentCount ?? this.currentCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (presetId.present) {
      map['preset_id'] = Variable<String>(presetId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (target.present) {
      map['target'] = Variable<int>(target.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (traditionTag.present) {
      map['tradition_tag'] = Variable<String>(traditionTag.value);
    }
    if (currentCount.present) {
      map['current_count'] = Variable<int>(currentCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PracticesCompanion(')
          ..write('id: $id, ')
          ..write('presetId: $presetId, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('target: $target, ')
          ..write('unit: $unit, ')
          ..write('traditionTag: $traditionTag, ')
          ..write('currentCount: $currentCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $CountHistoryTable extends CountHistory
    with TableInfo<$CountHistoryTable, CountHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CountHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _practiceIdMeta = const VerificationMeta(
    'practiceId',
  );
  @override
  late final GeneratedColumn<int> practiceId = GeneratedColumn<int>(
    'practice_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES practices (id)',
    ),
  );
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
    'count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    practiceId,
    count,
    timestamp,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'count_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<CountHistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('practice_id')) {
      context.handle(
        _practiceIdMeta,
        practiceId.isAcceptableOrUnknown(data['practice_id']!, _practiceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_practiceIdMeta);
    }
    if (data.containsKey('count')) {
      context.handle(
        _countMeta,
        count.isAcceptableOrUnknown(data['count']!, _countMeta),
      );
    } else if (isInserting) {
      context.missing(_countMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CountHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CountHistoryData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      practiceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}practice_id'],
      )!,
      count: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  $CountHistoryTable createAlias(String alias) {
    return $CountHistoryTable(attachedDatabase, alias);
  }
}

class CountHistoryData extends DataClass
    implements Insertable<CountHistoryData> {
  final int id;
  final int practiceId;
  final int count;
  final DateTime timestamp;
  final String? note;
  const CountHistoryData({
    required this.id,
    required this.practiceId,
    required this.count,
    required this.timestamp,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['practice_id'] = Variable<int>(practiceId);
    map['count'] = Variable<int>(count);
    map['timestamp'] = Variable<DateTime>(timestamp);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  CountHistoryCompanion toCompanion(bool nullToAbsent) {
    return CountHistoryCompanion(
      id: Value(id),
      practiceId: Value(practiceId),
      count: Value(count),
      timestamp: Value(timestamp),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory CountHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CountHistoryData(
      id: serializer.fromJson<int>(json['id']),
      practiceId: serializer.fromJson<int>(json['practiceId']),
      count: serializer.fromJson<int>(json['count']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'practiceId': serializer.toJson<int>(practiceId),
      'count': serializer.toJson<int>(count),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'note': serializer.toJson<String?>(note),
    };
  }

  CountHistoryData copyWith({
    int? id,
    int? practiceId,
    int? count,
    DateTime? timestamp,
    Value<String?> note = const Value.absent(),
  }) => CountHistoryData(
    id: id ?? this.id,
    practiceId: practiceId ?? this.practiceId,
    count: count ?? this.count,
    timestamp: timestamp ?? this.timestamp,
    note: note.present ? note.value : this.note,
  );
  CountHistoryData copyWithCompanion(CountHistoryCompanion data) {
    return CountHistoryData(
      id: data.id.present ? data.id.value : this.id,
      practiceId: data.practiceId.present
          ? data.practiceId.value
          : this.practiceId,
      count: data.count.present ? data.count.value : this.count,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CountHistoryData(')
          ..write('id: $id, ')
          ..write('practiceId: $practiceId, ')
          ..write('count: $count, ')
          ..write('timestamp: $timestamp, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, practiceId, count, timestamp, note);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CountHistoryData &&
          other.id == this.id &&
          other.practiceId == this.practiceId &&
          other.count == this.count &&
          other.timestamp == this.timestamp &&
          other.note == this.note);
}

class CountHistoryCompanion extends UpdateCompanion<CountHistoryData> {
  final Value<int> id;
  final Value<int> practiceId;
  final Value<int> count;
  final Value<DateTime> timestamp;
  final Value<String?> note;
  const CountHistoryCompanion({
    this.id = const Value.absent(),
    this.practiceId = const Value.absent(),
    this.count = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.note = const Value.absent(),
  });
  CountHistoryCompanion.insert({
    this.id = const Value.absent(),
    required int practiceId,
    required int count,
    this.timestamp = const Value.absent(),
    this.note = const Value.absent(),
  }) : practiceId = Value(practiceId),
       count = Value(count);
  static Insertable<CountHistoryData> custom({
    Expression<int>? id,
    Expression<int>? practiceId,
    Expression<int>? count,
    Expression<DateTime>? timestamp,
    Expression<String>? note,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (practiceId != null) 'practice_id': practiceId,
      if (count != null) 'count': count,
      if (timestamp != null) 'timestamp': timestamp,
      if (note != null) 'note': note,
    });
  }

  CountHistoryCompanion copyWith({
    Value<int>? id,
    Value<int>? practiceId,
    Value<int>? count,
    Value<DateTime>? timestamp,
    Value<String?>? note,
  }) {
    return CountHistoryCompanion(
      id: id ?? this.id,
      practiceId: practiceId ?? this.practiceId,
      count: count ?? this.count,
      timestamp: timestamp ?? this.timestamp,
      note: note ?? this.note,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (practiceId.present) {
      map['practice_id'] = Variable<int>(practiceId.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CountHistoryCompanion(')
          ..write('id: $id, ')
          ..write('practiceId: $practiceId, ')
          ..write('count: $count, ')
          ..write('timestamp: $timestamp, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PresetsTable presets = $PresetsTable(this);
  late final $PracticesTable practices = $PracticesTable(this);
  late final $CountHistoryTable countHistory = $CountHistoryTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    presets,
    practices,
    countHistory,
  ];
}

typedef $$PresetsTableCreateCompanionBuilder = PresetsCompanion Function({
  required String id,
  required String name,
  required String version,
  required String tradition,
  required String data,
  Value<int> rowid,
});
typedef $$PresetsTableUpdateCompanionBuilder = PresetsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> version,
  Value<String> tradition,
  Value<String> data,
  Value<int> rowid,
});

class $$PresetsTableFilterComposer
    extends Composer<_$AppDatabase, $PresetsTable> {
  $$PresetsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tradition => $composableBuilder(
    column: $table.tradition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PresetsTableOrderingComposer
    extends Composer<_$AppDatabase, $PresetsTable> {
  $$PresetsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tradition => $composableBuilder(
    column: $table.tradition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PresetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PresetsTable> {
  $$PresetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get tradition =>
      $composableBuilder(column: $table.tradition, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);
}

class $$PresetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PresetsTable,
          PresetRow,
          $$PresetsTableFilterComposer,
          $$PresetsTableOrderingComposer,
          $$PresetsTableAnnotationComposer,
          $$PresetsTableCreateCompanionBuilder,
          $$PresetsTableUpdateCompanionBuilder,
          (PresetRow, BaseReferences<_$AppDatabase, $PresetsTable, PresetRow>),
          PresetRow,
          PrefetchHooks Function()
        > {
  $$PresetsTableTableManager(_$AppDatabase db, $PresetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PresetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PresetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PresetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String> tradition = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PresetsCompanion(
                id: id,
                name: name,
                version: version,
                tradition: tradition,
                data: data,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String version,
                required String tradition,
                required String data,
                Value<int> rowid = const Value.absent(),
              }) => PresetsCompanion.insert(
                id: id,
                name: name,
                version: version,
                tradition: tradition,
                data: data,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PresetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PresetsTable,
      PresetRow,
      $$PresetsTableFilterComposer,
      $$PresetsTableOrderingComposer,
      $$PresetsTableAnnotationComposer,
      $$PresetsTableCreateCompanionBuilder,
      $$PresetsTableUpdateCompanionBuilder,
      (PresetRow, BaseReferences<_$AppDatabase, $PresetsTable, PresetRow>),
      PresetRow,
      PrefetchHooks Function()
    >;
typedef $$PracticesTableCreateCompanionBuilder = PracticesCompanion Function({
  Value<int> id,
  Value<String?> presetId,
  required String name,
  required String type,
  Value<int?> target,
  Value<String?> unit,
  required String traditionTag,
  Value<int> currentCount,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$PracticesTableUpdateCompanionBuilder = PracticesCompanion Function({
  Value<int> id,
  Value<String?> presetId,
  Value<String> name,
  Value<String> type,
  Value<int?> target,
  Value<String?> unit,
  Value<String> traditionTag,
  Value<int> currentCount,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

final class $$PracticesTableReferences
    extends BaseReferences<_$AppDatabase, $PracticesTable, Practice> {
  $$PracticesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CountHistoryTable, List<CountHistoryData>>
  _countHistoryRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.countHistory,
    aliasName: 'practices__id__count_history__practice_id',
  );

  $$CountHistoryTableProcessedTableManager get countHistoryRefs {
    final manager = $$CountHistoryTableTableManager(
      $_db,
      $_db.countHistory,
    ).filter((f) => f.practiceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_countHistoryRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PracticesTableFilterComposer
    extends Composer<_$AppDatabase, $PracticesTable> {
  $$PracticesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get presetId => $composableBuilder(
    column: $table.presetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get traditionTag => $composableBuilder(
    column: $table.traditionTag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentCount => $composableBuilder(
    column: $table.currentCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> countHistoryRefs(
    Expression<bool> Function($$CountHistoryTableFilterComposer f) f,
  ) {
    final $$CountHistoryTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.countHistory,
      getReferencedColumn: (t) => t.practiceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CountHistoryTableFilterComposer(
            $db: $db,
            $table: $db.countHistory,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PracticesTableOrderingComposer
    extends Composer<_$AppDatabase, $PracticesTable> {
  $$PracticesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get presetId => $composableBuilder(
    column: $table.presetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get traditionTag => $composableBuilder(
    column: $table.traditionTag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentCount => $composableBuilder(
    column: $table.currentCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PracticesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PracticesTable> {
  $$PracticesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get presetId =>
      $composableBuilder(column: $table.presetId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get target =>
      $composableBuilder(column: $table.target, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<String> get traditionTag => $composableBuilder(
    column: $table.traditionTag,
    builder: (column) => column,
  );

  GeneratedColumn<int> get currentCount => $composableBuilder(
    column: $table.currentCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> countHistoryRefs<T extends Object>(
    Expression<T> Function($$CountHistoryTableAnnotationComposer a) f,
  ) {
    final $$CountHistoryTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.countHistory,
      getReferencedColumn: (t) => t.practiceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CountHistoryTableAnnotationComposer(
            $db: $db,
            $table: $db.countHistory,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PracticesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PracticesTable,
          Practice,
          $$PracticesTableFilterComposer,
          $$PracticesTableOrderingComposer,
          $$PracticesTableAnnotationComposer,
          $$PracticesTableCreateCompanionBuilder,
          $$PracticesTableUpdateCompanionBuilder,
          (Practice, $$PracticesTableReferences),
          Practice,
          PrefetchHooks Function({bool countHistoryRefs})
        > {
  $$PracticesTableTableManager(_$AppDatabase db, $PracticesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PracticesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PracticesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PracticesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> presetId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int?> target = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<String> traditionTag = const Value.absent(),
                Value<int> currentCount = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PracticesCompanion(
                id: id,
                presetId: presetId,
                name: name,
                type: type,
                target: target,
                unit: unit,
                traditionTag: traditionTag,
                currentCount: currentCount,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> presetId = const Value.absent(),
                required String name,
                required String type,
                Value<int?> target = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                required String traditionTag,
                Value<int> currentCount = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PracticesCompanion.insert(
                id: id,
                presetId: presetId,
                name: name,
                type: type,
                target: target,
                unit: unit,
                traditionTag: traditionTag,
                currentCount: currentCount,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PracticesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({countHistoryRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (countHistoryRefs) db.countHistory],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (countHistoryRefs)
                    await $_getPrefetchedData<
                      Practice,
                      $PracticesTable,
                      CountHistoryData
                    >(
                      currentTable: table,
                      referencedTable: $$PracticesTableReferences
                          ._countHistoryRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$PracticesTableReferences(
                            db,
                            table,
                            p0,
                          ).countHistoryRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.practiceId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$PracticesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PracticesTable,
      Practice,
      $$PracticesTableFilterComposer,
      $$PracticesTableOrderingComposer,
      $$PracticesTableAnnotationComposer,
      $$PracticesTableCreateCompanionBuilder,
      $$PracticesTableUpdateCompanionBuilder,
      (Practice, $$PracticesTableReferences),
      Practice,
      PrefetchHooks Function({bool countHistoryRefs})
    >;
typedef $$CountHistoryTableCreateCompanionBuilder =
    CountHistoryCompanion Function({
      Value<int> id,
      required int practiceId,
      required int count,
      Value<DateTime> timestamp,
      Value<String?> note,
    });
typedef $$CountHistoryTableUpdateCompanionBuilder =
    CountHistoryCompanion Function({
      Value<int> id,
      Value<int> practiceId,
      Value<int> count,
      Value<DateTime> timestamp,
      Value<String?> note,
    });

final class $$CountHistoryTableReferences
    extends
        BaseReferences<_$AppDatabase, $CountHistoryTable, CountHistoryData> {
  $$CountHistoryTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PracticesTable _practiceIdTable(_$AppDatabase db) =>
      db.practices.createAlias('count_history__practice_id__practices__id');

  $$PracticesTableProcessedTableManager get practiceId {
    final $_column = $_itemColumn<int>('practice_id')!;

    final manager = $$PracticesTableTableManager(
      $_db,
      $_db.practices,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_practiceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CountHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $CountHistoryTable> {
  $$CountHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  $$PracticesTableFilterComposer get practiceId {
    final $$PracticesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.practiceId,
      referencedTable: $db.practices,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PracticesTableFilterComposer(
            $db: $db,
            $table: $db.practices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CountHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $CountHistoryTable> {
  $$CountHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  $$PracticesTableOrderingComposer get practiceId {
    final $$PracticesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.practiceId,
      referencedTable: $db.practices,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PracticesTableOrderingComposer(
            $db: $db,
            $table: $db.practices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CountHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $CountHistoryTable> {
  $$CountHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get count =>
      $composableBuilder(column: $table.count, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  $$PracticesTableAnnotationComposer get practiceId {
    final $$PracticesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.practiceId,
      referencedTable: $db.practices,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PracticesTableAnnotationComposer(
            $db: $db,
            $table: $db.practices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CountHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CountHistoryTable,
          CountHistoryData,
          $$CountHistoryTableFilterComposer,
          $$CountHistoryTableOrderingComposer,
          $$CountHistoryTableAnnotationComposer,
          $$CountHistoryTableCreateCompanionBuilder,
          $$CountHistoryTableUpdateCompanionBuilder,
          (CountHistoryData, $$CountHistoryTableReferences),
          CountHistoryData,
          PrefetchHooks Function({bool practiceId})
        > {
  $$CountHistoryTableTableManager(_$AppDatabase db, $CountHistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CountHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CountHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CountHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> practiceId = const Value.absent(),
                Value<int> count = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<String?> note = const Value.absent(),
              }) => CountHistoryCompanion(
                id: id,
                practiceId: practiceId,
                count: count,
                timestamp: timestamp,
                note: note,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int practiceId,
                required int count,
                Value<DateTime> timestamp = const Value.absent(),
                Value<String?> note = const Value.absent(),
              }) => CountHistoryCompanion.insert(
                id: id,
                practiceId: practiceId,
                count: count,
                timestamp: timestamp,
                note: note,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CountHistoryTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({practiceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (practiceId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.practiceId,
                        referencedTable: $$CountHistoryTableReferences
                            ._practiceIdTable(db),
                        referencedColumn: $$CountHistoryTableReferences
                            ._practiceIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CountHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CountHistoryTable,
      CountHistoryData,
      $$CountHistoryTableFilterComposer,
      $$CountHistoryTableOrderingComposer,
      $$CountHistoryTableAnnotationComposer,
      $$CountHistoryTableCreateCompanionBuilder,
      $$CountHistoryTableUpdateCompanionBuilder,
      (CountHistoryData, $$CountHistoryTableReferences),
      CountHistoryData,
      PrefetchHooks Function({bool practiceId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PresetsTableTableManager get presets =>
      $$PresetsTableTableManager(_db, _db.presets);
  $$PracticesTableTableManager get practices =>
      $$PracticesTableTableManager(_db, _db.practices);
  $$CountHistoryTableTableManager get countHistory =>
      $$CountHistoryTableTableManager(_db, _db.countHistory);
}
