// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mindtree_db.dart';

// ignore_for_file: type=lint
class $TopicsTable extends Topics with TableInfo<$TopicsTable, TopicRowData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TopicsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _goalMeta = const VerificationMeta('goal');
  @override
  late final GeneratedColumn<String> goal = GeneratedColumn<String>(
    'goal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('overview'),
  );
  static const VerificationMeta _targetLevelMeta = const VerificationMeta(
    'targetLevel',
  );
  @override
  late final GeneratedColumn<String> targetLevel = GeneratedColumn<String>(
    'target_level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('basic_understanding'),
  );
  static const VerificationMeta _timeBudgetMinutesMeta = const VerificationMeta(
    'timeBudgetMinutes',
  );
  @override
  late final GeneratedColumn<int> timeBudgetMinutes = GeneratedColumn<int>(
    'time_budget_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(60),
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    goal,
    targetLevel,
    timeBudgetMinutes,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'topics';
  @override
  VerificationContext validateIntegrity(
    Insertable<TopicRowData> instance, {
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
    if (data.containsKey('goal')) {
      context.handle(
        _goalMeta,
        goal.isAcceptableOrUnknown(data['goal']!, _goalMeta),
      );
    }
    if (data.containsKey('target_level')) {
      context.handle(
        _targetLevelMeta,
        targetLevel.isAcceptableOrUnknown(
          data['target_level']!,
          _targetLevelMeta,
        ),
      );
    }
    if (data.containsKey('time_budget_minutes')) {
      context.handle(
        _timeBudgetMinutesMeta,
        timeBudgetMinutes.isAcceptableOrUnknown(
          data['time_budget_minutes']!,
          _timeBudgetMinutesMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TopicRowData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TopicRowData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      goal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}goal'],
      )!,
      targetLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_level'],
      )!,
      timeBudgetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_budget_minutes'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TopicsTable createAlias(String alias) {
    return $TopicsTable(attachedDatabase, alias);
  }
}

class TopicRowData extends DataClass implements Insertable<TopicRowData> {
  final String id;
  final String name;
  final String goal;
  final String targetLevel;
  final int timeBudgetMinutes;
  final DateTime createdAt;
  const TopicRowData({
    required this.id,
    required this.name,
    required this.goal,
    required this.targetLevel,
    required this.timeBudgetMinutes,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['goal'] = Variable<String>(goal);
    map['target_level'] = Variable<String>(targetLevel);
    map['time_budget_minutes'] = Variable<int>(timeBudgetMinutes);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TopicsCompanion toCompanion(bool nullToAbsent) {
    return TopicsCompanion(
      id: Value(id),
      name: Value(name),
      goal: Value(goal),
      targetLevel: Value(targetLevel),
      timeBudgetMinutes: Value(timeBudgetMinutes),
      createdAt: Value(createdAt),
    );
  }

  factory TopicRowData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TopicRowData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      goal: serializer.fromJson<String>(json['goal']),
      targetLevel: serializer.fromJson<String>(json['targetLevel']),
      timeBudgetMinutes: serializer.fromJson<int>(json['timeBudgetMinutes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'goal': serializer.toJson<String>(goal),
      'targetLevel': serializer.toJson<String>(targetLevel),
      'timeBudgetMinutes': serializer.toJson<int>(timeBudgetMinutes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  TopicRowData copyWith({
    String? id,
    String? name,
    String? goal,
    String? targetLevel,
    int? timeBudgetMinutes,
    DateTime? createdAt,
  }) => TopicRowData(
    id: id ?? this.id,
    name: name ?? this.name,
    goal: goal ?? this.goal,
    targetLevel: targetLevel ?? this.targetLevel,
    timeBudgetMinutes: timeBudgetMinutes ?? this.timeBudgetMinutes,
    createdAt: createdAt ?? this.createdAt,
  );
  TopicRowData copyWithCompanion(TopicsCompanion data) {
    return TopicRowData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      goal: data.goal.present ? data.goal.value : this.goal,
      targetLevel: data.targetLevel.present
          ? data.targetLevel.value
          : this.targetLevel,
      timeBudgetMinutes: data.timeBudgetMinutes.present
          ? data.timeBudgetMinutes.value
          : this.timeBudgetMinutes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TopicRowData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('goal: $goal, ')
          ..write('targetLevel: $targetLevel, ')
          ..write('timeBudgetMinutes: $timeBudgetMinutes, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, goal, targetLevel, timeBudgetMinutes, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TopicRowData &&
          other.id == this.id &&
          other.name == this.name &&
          other.goal == this.goal &&
          other.targetLevel == this.targetLevel &&
          other.timeBudgetMinutes == this.timeBudgetMinutes &&
          other.createdAt == this.createdAt);
}

class TopicsCompanion extends UpdateCompanion<TopicRowData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> goal;
  final Value<String> targetLevel;
  final Value<int> timeBudgetMinutes;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const TopicsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.goal = const Value.absent(),
    this.targetLevel = const Value.absent(),
    this.timeBudgetMinutes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TopicsCompanion.insert({
    required String id,
    required String name,
    this.goal = const Value.absent(),
    this.targetLevel = const Value.absent(),
    this.timeBudgetMinutes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<TopicRowData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? goal,
    Expression<String>? targetLevel,
    Expression<int>? timeBudgetMinutes,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (goal != null) 'goal': goal,
      if (targetLevel != null) 'target_level': targetLevel,
      if (timeBudgetMinutes != null) 'time_budget_minutes': timeBudgetMinutes,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TopicsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? goal,
    Value<String>? targetLevel,
    Value<int>? timeBudgetMinutes,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return TopicsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      goal: goal ?? this.goal,
      targetLevel: targetLevel ?? this.targetLevel,
      timeBudgetMinutes: timeBudgetMinutes ?? this.timeBudgetMinutes,
      createdAt: createdAt ?? this.createdAt,
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
    if (goal.present) {
      map['goal'] = Variable<String>(goal.value);
    }
    if (targetLevel.present) {
      map['target_level'] = Variable<String>(targetLevel.value);
    }
    if (timeBudgetMinutes.present) {
      map['time_budget_minutes'] = Variable<int>(timeBudgetMinutes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TopicsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('goal: $goal, ')
          ..write('targetLevel: $targetLevel, ')
          ..write('timeBudgetMinutes: $timeBudgetMinutes, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KnowledgeNodesTable extends KnowledgeNodes
    with TableInfo<$KnowledgeNodesTable, KnowledgeNodeRowData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KnowledgeNodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicIdMeta = const VerificationMeta(
    'topicId',
  );
  @override
  late final GeneratedColumn<String> topicId = GeneratedColumn<String>(
    'topic_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES topics (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES knowledge_nodes (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _oneLinerMeta = const VerificationMeta(
    'oneLiner',
  );
  @override
  late final GeneratedColumn<String> oneLiner = GeneratedColumn<String>(
    'one_liner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _detailsMeta = const VerificationMeta(
    'details',
  );
  @override
  late final GeneratedColumn<String> details = GeneratedColumn<String>(
    'details',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _analogyMeta = const VerificationMeta(
    'analogy',
  );
  @override
  late final GeneratedColumn<String> analogy = GeneratedColumn<String>(
    'analogy',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _conceptTypeMeta = const VerificationMeta(
    'conceptType',
  );
  @override
  late final GeneratedColumn<String> conceptType = GeneratedColumn<String>(
    'concept_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _importanceMeta = const VerificationMeta(
    'importance',
  );
  @override
  late final GeneratedColumn<double> importance = GeneratedColumn<double>(
    'importance',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.5),
  );
  static const VerificationMeta _difficultyMeta = const VerificationMeta(
    'difficulty',
  );
  @override
  late final GeneratedColumn<double> difficulty = GeneratedColumn<double>(
    'difficulty',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.5),
  );
  static const VerificationMeta _estimatedTimeMinutesMeta =
      const VerificationMeta('estimatedTimeMinutes');
  @override
  late final GeneratedColumn<int> estimatedTimeMinutes = GeneratedColumn<int>(
    'estimated_time_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(5),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('new'),
  );
  static const VerificationMeta _contentLoadedMeta = const VerificationMeta(
    'contentLoaded',
  );
  @override
  late final GeneratedColumn<bool> contentLoaded = GeneratedColumn<bool>(
    'content_loaded',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("content_loaded" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _leafMeta = const VerificationMeta('leaf');
  @override
  late final GeneratedColumn<bool> leaf = GeneratedColumn<bool>(
    'leaf',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("leaf" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<int> level = GeneratedColumn<int>(
    'level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _relationsJsonMeta = const VerificationMeta(
    'relationsJson',
  );
  @override
  late final GeneratedColumn<String> relationsJson = GeneratedColumn<String>(
    'relations_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _sequencesJsonMeta = const VerificationMeta(
    'sequencesJson',
  );
  @override
  late final GeneratedColumn<String> sequencesJson = GeneratedColumn<String>(
    'sequences_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _sourcesJsonMeta = const VerificationMeta(
    'sourcesJson',
  );
  @override
  late final GeneratedColumn<String> sourcesJson = GeneratedColumn<String>(
    'sources_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    topicId,
    parentId,
    label,
    oneLiner,
    details,
    analogy,
    conceptType,
    importance,
    difficulty,
    estimatedTimeMinutes,
    state,
    contentLoaded,
    leaf,
    level,
    relationsJson,
    sequencesJson,
    sourcesJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'knowledge_nodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<KnowledgeNodeRowData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('topic_id')) {
      context.handle(
        _topicIdMeta,
        topicId.isAcceptableOrUnknown(data['topic_id']!, _topicIdMeta),
      );
    } else if (isInserting) {
      context.missing(_topicIdMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('one_liner')) {
      context.handle(
        _oneLinerMeta,
        oneLiner.isAcceptableOrUnknown(data['one_liner']!, _oneLinerMeta),
      );
    }
    if (data.containsKey('details')) {
      context.handle(
        _detailsMeta,
        details.isAcceptableOrUnknown(data['details']!, _detailsMeta),
      );
    }
    if (data.containsKey('analogy')) {
      context.handle(
        _analogyMeta,
        analogy.isAcceptableOrUnknown(data['analogy']!, _analogyMeta),
      );
    }
    if (data.containsKey('concept_type')) {
      context.handle(
        _conceptTypeMeta,
        conceptType.isAcceptableOrUnknown(
          data['concept_type']!,
          _conceptTypeMeta,
        ),
      );
    }
    if (data.containsKey('importance')) {
      context.handle(
        _importanceMeta,
        importance.isAcceptableOrUnknown(data['importance']!, _importanceMeta),
      );
    }
    if (data.containsKey('difficulty')) {
      context.handle(
        _difficultyMeta,
        difficulty.isAcceptableOrUnknown(data['difficulty']!, _difficultyMeta),
      );
    }
    if (data.containsKey('estimated_time_minutes')) {
      context.handle(
        _estimatedTimeMinutesMeta,
        estimatedTimeMinutes.isAcceptableOrUnknown(
          data['estimated_time_minutes']!,
          _estimatedTimeMinutesMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('content_loaded')) {
      context.handle(
        _contentLoadedMeta,
        contentLoaded.isAcceptableOrUnknown(
          data['content_loaded']!,
          _contentLoadedMeta,
        ),
      );
    }
    if (data.containsKey('leaf')) {
      context.handle(
        _leafMeta,
        leaf.isAcceptableOrUnknown(data['leaf']!, _leafMeta),
      );
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    }
    if (data.containsKey('relations_json')) {
      context.handle(
        _relationsJsonMeta,
        relationsJson.isAcceptableOrUnknown(
          data['relations_json']!,
          _relationsJsonMeta,
        ),
      );
    }
    if (data.containsKey('sequences_json')) {
      context.handle(
        _sequencesJsonMeta,
        sequencesJson.isAcceptableOrUnknown(
          data['sequences_json']!,
          _sequencesJsonMeta,
        ),
      );
    }
    if (data.containsKey('sources_json')) {
      context.handle(
        _sourcesJsonMeta,
        sourcesJson.isAcceptableOrUnknown(
          data['sources_json']!,
          _sourcesJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  KnowledgeNodeRowData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KnowledgeNodeRowData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      topicId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic_id'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      oneLiner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}one_liner'],
      )!,
      details: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}details'],
      )!,
      analogy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}analogy'],
      ),
      conceptType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}concept_type'],
      ),
      importance: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}importance'],
      )!,
      difficulty: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}difficulty'],
      )!,
      estimatedTimeMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estimated_time_minutes'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      contentLoaded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}content_loaded'],
      )!,
      leaf: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}leaf'],
      )!,
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}level'],
      )!,
      relationsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relations_json'],
      )!,
      sequencesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sequences_json'],
      )!,
      sourcesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sources_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $KnowledgeNodesTable createAlias(String alias) {
    return $KnowledgeNodesTable(attachedDatabase, alias);
  }
}

class KnowledgeNodeRowData extends DataClass
    implements Insertable<KnowledgeNodeRowData> {
  final String id;
  final String topicId;
  final String? parentId;
  final String label;
  final String oneLiner;
  final String details;
  final String? analogy;
  final String? conceptType;
  final double importance;
  final double difficulty;
  final int estimatedTimeMinutes;
  final String state;
  final bool contentLoaded;
  final bool leaf;
  final int level;
  final String relationsJson;
  final String sequencesJson;
  final String sourcesJson;
  final DateTime createdAt;
  const KnowledgeNodeRowData({
    required this.id,
    required this.topicId,
    this.parentId,
    required this.label,
    required this.oneLiner,
    required this.details,
    this.analogy,
    this.conceptType,
    required this.importance,
    required this.difficulty,
    required this.estimatedTimeMinutes,
    required this.state,
    required this.contentLoaded,
    required this.leaf,
    required this.level,
    required this.relationsJson,
    required this.sequencesJson,
    required this.sourcesJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['topic_id'] = Variable<String>(topicId);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['label'] = Variable<String>(label);
    map['one_liner'] = Variable<String>(oneLiner);
    map['details'] = Variable<String>(details);
    if (!nullToAbsent || analogy != null) {
      map['analogy'] = Variable<String>(analogy);
    }
    if (!nullToAbsent || conceptType != null) {
      map['concept_type'] = Variable<String>(conceptType);
    }
    map['importance'] = Variable<double>(importance);
    map['difficulty'] = Variable<double>(difficulty);
    map['estimated_time_minutes'] = Variable<int>(estimatedTimeMinutes);
    map['state'] = Variable<String>(state);
    map['content_loaded'] = Variable<bool>(contentLoaded);
    map['leaf'] = Variable<bool>(leaf);
    map['level'] = Variable<int>(level);
    map['relations_json'] = Variable<String>(relationsJson);
    map['sequences_json'] = Variable<String>(sequencesJson);
    map['sources_json'] = Variable<String>(sourcesJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  KnowledgeNodesCompanion toCompanion(bool nullToAbsent) {
    return KnowledgeNodesCompanion(
      id: Value(id),
      topicId: Value(topicId),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      label: Value(label),
      oneLiner: Value(oneLiner),
      details: Value(details),
      analogy: analogy == null && nullToAbsent
          ? const Value.absent()
          : Value(analogy),
      conceptType: conceptType == null && nullToAbsent
          ? const Value.absent()
          : Value(conceptType),
      importance: Value(importance),
      difficulty: Value(difficulty),
      estimatedTimeMinutes: Value(estimatedTimeMinutes),
      state: Value(state),
      contentLoaded: Value(contentLoaded),
      leaf: Value(leaf),
      level: Value(level),
      relationsJson: Value(relationsJson),
      sequencesJson: Value(sequencesJson),
      sourcesJson: Value(sourcesJson),
      createdAt: Value(createdAt),
    );
  }

  factory KnowledgeNodeRowData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KnowledgeNodeRowData(
      id: serializer.fromJson<String>(json['id']),
      topicId: serializer.fromJson<String>(json['topicId']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      label: serializer.fromJson<String>(json['label']),
      oneLiner: serializer.fromJson<String>(json['oneLiner']),
      details: serializer.fromJson<String>(json['details']),
      analogy: serializer.fromJson<String?>(json['analogy']),
      conceptType: serializer.fromJson<String?>(json['conceptType']),
      importance: serializer.fromJson<double>(json['importance']),
      difficulty: serializer.fromJson<double>(json['difficulty']),
      estimatedTimeMinutes: serializer.fromJson<int>(
        json['estimatedTimeMinutes'],
      ),
      state: serializer.fromJson<String>(json['state']),
      contentLoaded: serializer.fromJson<bool>(json['contentLoaded']),
      leaf: serializer.fromJson<bool>(json['leaf']),
      level: serializer.fromJson<int>(json['level']),
      relationsJson: serializer.fromJson<String>(json['relationsJson']),
      sequencesJson: serializer.fromJson<String>(json['sequencesJson']),
      sourcesJson: serializer.fromJson<String>(json['sourcesJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'topicId': serializer.toJson<String>(topicId),
      'parentId': serializer.toJson<String?>(parentId),
      'label': serializer.toJson<String>(label),
      'oneLiner': serializer.toJson<String>(oneLiner),
      'details': serializer.toJson<String>(details),
      'analogy': serializer.toJson<String?>(analogy),
      'conceptType': serializer.toJson<String?>(conceptType),
      'importance': serializer.toJson<double>(importance),
      'difficulty': serializer.toJson<double>(difficulty),
      'estimatedTimeMinutes': serializer.toJson<int>(estimatedTimeMinutes),
      'state': serializer.toJson<String>(state),
      'contentLoaded': serializer.toJson<bool>(contentLoaded),
      'leaf': serializer.toJson<bool>(leaf),
      'level': serializer.toJson<int>(level),
      'relationsJson': serializer.toJson<String>(relationsJson),
      'sequencesJson': serializer.toJson<String>(sequencesJson),
      'sourcesJson': serializer.toJson<String>(sourcesJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  KnowledgeNodeRowData copyWith({
    String? id,
    String? topicId,
    Value<String?> parentId = const Value.absent(),
    String? label,
    String? oneLiner,
    String? details,
    Value<String?> analogy = const Value.absent(),
    Value<String?> conceptType = const Value.absent(),
    double? importance,
    double? difficulty,
    int? estimatedTimeMinutes,
    String? state,
    bool? contentLoaded,
    bool? leaf,
    int? level,
    String? relationsJson,
    String? sequencesJson,
    String? sourcesJson,
    DateTime? createdAt,
  }) => KnowledgeNodeRowData(
    id: id ?? this.id,
    topicId: topicId ?? this.topicId,
    parentId: parentId.present ? parentId.value : this.parentId,
    label: label ?? this.label,
    oneLiner: oneLiner ?? this.oneLiner,
    details: details ?? this.details,
    analogy: analogy.present ? analogy.value : this.analogy,
    conceptType: conceptType.present ? conceptType.value : this.conceptType,
    importance: importance ?? this.importance,
    difficulty: difficulty ?? this.difficulty,
    estimatedTimeMinutes: estimatedTimeMinutes ?? this.estimatedTimeMinutes,
    state: state ?? this.state,
    contentLoaded: contentLoaded ?? this.contentLoaded,
    leaf: leaf ?? this.leaf,
    level: level ?? this.level,
    relationsJson: relationsJson ?? this.relationsJson,
    sequencesJson: sequencesJson ?? this.sequencesJson,
    sourcesJson: sourcesJson ?? this.sourcesJson,
    createdAt: createdAt ?? this.createdAt,
  );
  KnowledgeNodeRowData copyWithCompanion(KnowledgeNodesCompanion data) {
    return KnowledgeNodeRowData(
      id: data.id.present ? data.id.value : this.id,
      topicId: data.topicId.present ? data.topicId.value : this.topicId,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      label: data.label.present ? data.label.value : this.label,
      oneLiner: data.oneLiner.present ? data.oneLiner.value : this.oneLiner,
      details: data.details.present ? data.details.value : this.details,
      analogy: data.analogy.present ? data.analogy.value : this.analogy,
      conceptType: data.conceptType.present
          ? data.conceptType.value
          : this.conceptType,
      importance: data.importance.present
          ? data.importance.value
          : this.importance,
      difficulty: data.difficulty.present
          ? data.difficulty.value
          : this.difficulty,
      estimatedTimeMinutes: data.estimatedTimeMinutes.present
          ? data.estimatedTimeMinutes.value
          : this.estimatedTimeMinutes,
      state: data.state.present ? data.state.value : this.state,
      contentLoaded: data.contentLoaded.present
          ? data.contentLoaded.value
          : this.contentLoaded,
      leaf: data.leaf.present ? data.leaf.value : this.leaf,
      level: data.level.present ? data.level.value : this.level,
      relationsJson: data.relationsJson.present
          ? data.relationsJson.value
          : this.relationsJson,
      sequencesJson: data.sequencesJson.present
          ? data.sequencesJson.value
          : this.sequencesJson,
      sourcesJson: data.sourcesJson.present
          ? data.sourcesJson.value
          : this.sourcesJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KnowledgeNodeRowData(')
          ..write('id: $id, ')
          ..write('topicId: $topicId, ')
          ..write('parentId: $parentId, ')
          ..write('label: $label, ')
          ..write('oneLiner: $oneLiner, ')
          ..write('details: $details, ')
          ..write('analogy: $analogy, ')
          ..write('conceptType: $conceptType, ')
          ..write('importance: $importance, ')
          ..write('difficulty: $difficulty, ')
          ..write('estimatedTimeMinutes: $estimatedTimeMinutes, ')
          ..write('state: $state, ')
          ..write('contentLoaded: $contentLoaded, ')
          ..write('leaf: $leaf, ')
          ..write('level: $level, ')
          ..write('relationsJson: $relationsJson, ')
          ..write('sequencesJson: $sequencesJson, ')
          ..write('sourcesJson: $sourcesJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    topicId,
    parentId,
    label,
    oneLiner,
    details,
    analogy,
    conceptType,
    importance,
    difficulty,
    estimatedTimeMinutes,
    state,
    contentLoaded,
    leaf,
    level,
    relationsJson,
    sequencesJson,
    sourcesJson,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KnowledgeNodeRowData &&
          other.id == this.id &&
          other.topicId == this.topicId &&
          other.parentId == this.parentId &&
          other.label == this.label &&
          other.oneLiner == this.oneLiner &&
          other.details == this.details &&
          other.analogy == this.analogy &&
          other.conceptType == this.conceptType &&
          other.importance == this.importance &&
          other.difficulty == this.difficulty &&
          other.estimatedTimeMinutes == this.estimatedTimeMinutes &&
          other.state == this.state &&
          other.contentLoaded == this.contentLoaded &&
          other.leaf == this.leaf &&
          other.level == this.level &&
          other.relationsJson == this.relationsJson &&
          other.sequencesJson == this.sequencesJson &&
          other.sourcesJson == this.sourcesJson &&
          other.createdAt == this.createdAt);
}

class KnowledgeNodesCompanion extends UpdateCompanion<KnowledgeNodeRowData> {
  final Value<String> id;
  final Value<String> topicId;
  final Value<String?> parentId;
  final Value<String> label;
  final Value<String> oneLiner;
  final Value<String> details;
  final Value<String?> analogy;
  final Value<String?> conceptType;
  final Value<double> importance;
  final Value<double> difficulty;
  final Value<int> estimatedTimeMinutes;
  final Value<String> state;
  final Value<bool> contentLoaded;
  final Value<bool> leaf;
  final Value<int> level;
  final Value<String> relationsJson;
  final Value<String> sequencesJson;
  final Value<String> sourcesJson;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const KnowledgeNodesCompanion({
    this.id = const Value.absent(),
    this.topicId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.label = const Value.absent(),
    this.oneLiner = const Value.absent(),
    this.details = const Value.absent(),
    this.analogy = const Value.absent(),
    this.conceptType = const Value.absent(),
    this.importance = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.estimatedTimeMinutes = const Value.absent(),
    this.state = const Value.absent(),
    this.contentLoaded = const Value.absent(),
    this.leaf = const Value.absent(),
    this.level = const Value.absent(),
    this.relationsJson = const Value.absent(),
    this.sequencesJson = const Value.absent(),
    this.sourcesJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KnowledgeNodesCompanion.insert({
    required String id,
    required String topicId,
    this.parentId = const Value.absent(),
    required String label,
    this.oneLiner = const Value.absent(),
    this.details = const Value.absent(),
    this.analogy = const Value.absent(),
    this.conceptType = const Value.absent(),
    this.importance = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.estimatedTimeMinutes = const Value.absent(),
    this.state = const Value.absent(),
    this.contentLoaded = const Value.absent(),
    this.leaf = const Value.absent(),
    this.level = const Value.absent(),
    this.relationsJson = const Value.absent(),
    this.sequencesJson = const Value.absent(),
    this.sourcesJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       topicId = Value(topicId),
       label = Value(label);
  static Insertable<KnowledgeNodeRowData> custom({
    Expression<String>? id,
    Expression<String>? topicId,
    Expression<String>? parentId,
    Expression<String>? label,
    Expression<String>? oneLiner,
    Expression<String>? details,
    Expression<String>? analogy,
    Expression<String>? conceptType,
    Expression<double>? importance,
    Expression<double>? difficulty,
    Expression<int>? estimatedTimeMinutes,
    Expression<String>? state,
    Expression<bool>? contentLoaded,
    Expression<bool>? leaf,
    Expression<int>? level,
    Expression<String>? relationsJson,
    Expression<String>? sequencesJson,
    Expression<String>? sourcesJson,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (topicId != null) 'topic_id': topicId,
      if (parentId != null) 'parent_id': parentId,
      if (label != null) 'label': label,
      if (oneLiner != null) 'one_liner': oneLiner,
      if (details != null) 'details': details,
      if (analogy != null) 'analogy': analogy,
      if (conceptType != null) 'concept_type': conceptType,
      if (importance != null) 'importance': importance,
      if (difficulty != null) 'difficulty': difficulty,
      if (estimatedTimeMinutes != null)
        'estimated_time_minutes': estimatedTimeMinutes,
      if (state != null) 'state': state,
      if (contentLoaded != null) 'content_loaded': contentLoaded,
      if (leaf != null) 'leaf': leaf,
      if (level != null) 'level': level,
      if (relationsJson != null) 'relations_json': relationsJson,
      if (sequencesJson != null) 'sequences_json': sequencesJson,
      if (sourcesJson != null) 'sources_json': sourcesJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KnowledgeNodesCompanion copyWith({
    Value<String>? id,
    Value<String>? topicId,
    Value<String?>? parentId,
    Value<String>? label,
    Value<String>? oneLiner,
    Value<String>? details,
    Value<String?>? analogy,
    Value<String?>? conceptType,
    Value<double>? importance,
    Value<double>? difficulty,
    Value<int>? estimatedTimeMinutes,
    Value<String>? state,
    Value<bool>? contentLoaded,
    Value<bool>? leaf,
    Value<int>? level,
    Value<String>? relationsJson,
    Value<String>? sequencesJson,
    Value<String>? sourcesJson,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return KnowledgeNodesCompanion(
      id: id ?? this.id,
      topicId: topicId ?? this.topicId,
      parentId: parentId ?? this.parentId,
      label: label ?? this.label,
      oneLiner: oneLiner ?? this.oneLiner,
      details: details ?? this.details,
      analogy: analogy ?? this.analogy,
      conceptType: conceptType ?? this.conceptType,
      importance: importance ?? this.importance,
      difficulty: difficulty ?? this.difficulty,
      estimatedTimeMinutes: estimatedTimeMinutes ?? this.estimatedTimeMinutes,
      state: state ?? this.state,
      contentLoaded: contentLoaded ?? this.contentLoaded,
      leaf: leaf ?? this.leaf,
      level: level ?? this.level,
      relationsJson: relationsJson ?? this.relationsJson,
      sequencesJson: sequencesJson ?? this.sequencesJson,
      sourcesJson: sourcesJson ?? this.sourcesJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (topicId.present) {
      map['topic_id'] = Variable<String>(topicId.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (oneLiner.present) {
      map['one_liner'] = Variable<String>(oneLiner.value);
    }
    if (details.present) {
      map['details'] = Variable<String>(details.value);
    }
    if (analogy.present) {
      map['analogy'] = Variable<String>(analogy.value);
    }
    if (conceptType.present) {
      map['concept_type'] = Variable<String>(conceptType.value);
    }
    if (importance.present) {
      map['importance'] = Variable<double>(importance.value);
    }
    if (difficulty.present) {
      map['difficulty'] = Variable<double>(difficulty.value);
    }
    if (estimatedTimeMinutes.present) {
      map['estimated_time_minutes'] = Variable<int>(estimatedTimeMinutes.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (contentLoaded.present) {
      map['content_loaded'] = Variable<bool>(contentLoaded.value);
    }
    if (leaf.present) {
      map['leaf'] = Variable<bool>(leaf.value);
    }
    if (level.present) {
      map['level'] = Variable<int>(level.value);
    }
    if (relationsJson.present) {
      map['relations_json'] = Variable<String>(relationsJson.value);
    }
    if (sequencesJson.present) {
      map['sequences_json'] = Variable<String>(sequencesJson.value);
    }
    if (sourcesJson.present) {
      map['sources_json'] = Variable<String>(sourcesJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KnowledgeNodesCompanion(')
          ..write('id: $id, ')
          ..write('topicId: $topicId, ')
          ..write('parentId: $parentId, ')
          ..write('label: $label, ')
          ..write('oneLiner: $oneLiner, ')
          ..write('details: $details, ')
          ..write('analogy: $analogy, ')
          ..write('conceptType: $conceptType, ')
          ..write('importance: $importance, ')
          ..write('difficulty: $difficulty, ')
          ..write('estimatedTimeMinutes: $estimatedTimeMinutes, ')
          ..write('state: $state, ')
          ..write('contentLoaded: $contentLoaded, ')
          ..write('leaf: $leaf, ')
          ..write('level: $level, ')
          ..write('relationsJson: $relationsJson, ')
          ..write('sequencesJson: $sequencesJson, ')
          ..write('sourcesJson: $sourcesJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LearningJourneysTable extends LearningJourneys
    with TableInfo<$LearningJourneysTable, LearningJourneyRowData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LearningJourneysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicIdMeta = const VerificationMeta(
    'topicId',
  );
  @override
  late final GeneratedColumn<String> topicId = GeneratedColumn<String>(
    'topic_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES topics (id) ON DELETE CASCADE',
    ),
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
  @override
  List<GeneratedColumn> get $columns => [id, topicId, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'learning_journeys';
  @override
  VerificationContext validateIntegrity(
    Insertable<LearningJourneyRowData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('topic_id')) {
      context.handle(
        _topicIdMeta,
        topicId.isAcceptableOrUnknown(data['topic_id']!, _topicIdMeta),
      );
    } else if (isInserting) {
      context.missing(_topicIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LearningJourneyRowData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LearningJourneyRowData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      topicId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $LearningJourneysTable createAlias(String alias) {
    return $LearningJourneysTable(attachedDatabase, alias);
  }
}

class LearningJourneyRowData extends DataClass
    implements Insertable<LearningJourneyRowData> {
  final String id;
  final String topicId;
  final DateTime createdAt;
  const LearningJourneyRowData({
    required this.id,
    required this.topicId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['topic_id'] = Variable<String>(topicId);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  LearningJourneysCompanion toCompanion(bool nullToAbsent) {
    return LearningJourneysCompanion(
      id: Value(id),
      topicId: Value(topicId),
      createdAt: Value(createdAt),
    );
  }

  factory LearningJourneyRowData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LearningJourneyRowData(
      id: serializer.fromJson<String>(json['id']),
      topicId: serializer.fromJson<String>(json['topicId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'topicId': serializer.toJson<String>(topicId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  LearningJourneyRowData copyWith({
    String? id,
    String? topicId,
    DateTime? createdAt,
  }) => LearningJourneyRowData(
    id: id ?? this.id,
    topicId: topicId ?? this.topicId,
    createdAt: createdAt ?? this.createdAt,
  );
  LearningJourneyRowData copyWithCompanion(LearningJourneysCompanion data) {
    return LearningJourneyRowData(
      id: data.id.present ? data.id.value : this.id,
      topicId: data.topicId.present ? data.topicId.value : this.topicId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LearningJourneyRowData(')
          ..write('id: $id, ')
          ..write('topicId: $topicId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, topicId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LearningJourneyRowData &&
          other.id == this.id &&
          other.topicId == this.topicId &&
          other.createdAt == this.createdAt);
}

class LearningJourneysCompanion
    extends UpdateCompanion<LearningJourneyRowData> {
  final Value<String> id;
  final Value<String> topicId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const LearningJourneysCompanion({
    this.id = const Value.absent(),
    this.topicId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LearningJourneysCompanion.insert({
    required String id,
    required String topicId,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       topicId = Value(topicId);
  static Insertable<LearningJourneyRowData> custom({
    Expression<String>? id,
    Expression<String>? topicId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (topicId != null) 'topic_id': topicId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LearningJourneysCompanion copyWith({
    Value<String>? id,
    Value<String>? topicId,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return LearningJourneysCompanion(
      id: id ?? this.id,
      topicId: topicId ?? this.topicId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (topicId.present) {
      map['topic_id'] = Variable<String>(topicId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LearningJourneysCompanion(')
          ..write('id: $id, ')
          ..write('topicId: $topicId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LearningMilestonesTable extends LearningMilestones
    with TableInfo<$LearningMilestonesTable, LearningMilestoneRowData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LearningMilestonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _journeyIdMeta = const VerificationMeta(
    'journeyId',
  );
  @override
  late final GeneratedColumn<String> journeyId = GeneratedColumn<String>(
    'journey_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES learning_journeys (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<String> level = GeneratedColumn<String>(
    'level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _capabilitiesJsonMeta = const VerificationMeta(
    'capabilitiesJson',
  );
  @override
  late final GeneratedColumn<String> capabilitiesJson = GeneratedColumn<String>(
    'capabilities_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _estimatedHoursMeta = const VerificationMeta(
    'estimatedHours',
  );
  @override
  late final GeneratedColumn<double> estimatedHours = GeneratedColumn<double>(
    'estimated_hours',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('not_started'),
  );
  static const VerificationMeta _alternativePathsJsonMeta =
      const VerificationMeta('alternativePathsJson');
  @override
  late final GeneratedColumn<String> alternativePathsJson =
      GeneratedColumn<String>(
        'alternative_paths_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    journeyId,
    level,
    title,
    description,
    capabilitiesJson,
    estimatedHours,
    status,
    alternativePathsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'learning_milestones';
  @override
  VerificationContext validateIntegrity(
    Insertable<LearningMilestoneRowData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('journey_id')) {
      context.handle(
        _journeyIdMeta,
        journeyId.isAcceptableOrUnknown(data['journey_id']!, _journeyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_journeyIdMeta);
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    } else if (isInserting) {
      context.missing(_levelMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('capabilities_json')) {
      context.handle(
        _capabilitiesJsonMeta,
        capabilitiesJson.isAcceptableOrUnknown(
          data['capabilities_json']!,
          _capabilitiesJsonMeta,
        ),
      );
    }
    if (data.containsKey('estimated_hours')) {
      context.handle(
        _estimatedHoursMeta,
        estimatedHours.isAcceptableOrUnknown(
          data['estimated_hours']!,
          _estimatedHoursMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('alternative_paths_json')) {
      context.handle(
        _alternativePathsJsonMeta,
        alternativePathsJson.isAcceptableOrUnknown(
          data['alternative_paths_json']!,
          _alternativePathsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LearningMilestoneRowData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LearningMilestoneRowData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      journeyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}journey_id'],
      )!,
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}level'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      capabilitiesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capabilities_json'],
      )!,
      estimatedHours: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}estimated_hours'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      alternativePathsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alternative_paths_json'],
      )!,
    );
  }

  @override
  $LearningMilestonesTable createAlias(String alias) {
    return $LearningMilestonesTable(attachedDatabase, alias);
  }
}

class LearningMilestoneRowData extends DataClass
    implements Insertable<LearningMilestoneRowData> {
  final String id;
  final String journeyId;
  final String level;
  final String title;
  final String description;
  final String capabilitiesJson;
  final double estimatedHours;
  final String status;
  final String alternativePathsJson;
  const LearningMilestoneRowData({
    required this.id,
    required this.journeyId,
    required this.level,
    required this.title,
    required this.description,
    required this.capabilitiesJson,
    required this.estimatedHours,
    required this.status,
    required this.alternativePathsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['journey_id'] = Variable<String>(journeyId);
    map['level'] = Variable<String>(level);
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    map['capabilities_json'] = Variable<String>(capabilitiesJson);
    map['estimated_hours'] = Variable<double>(estimatedHours);
    map['status'] = Variable<String>(status);
    map['alternative_paths_json'] = Variable<String>(alternativePathsJson);
    return map;
  }

  LearningMilestonesCompanion toCompanion(bool nullToAbsent) {
    return LearningMilestonesCompanion(
      id: Value(id),
      journeyId: Value(journeyId),
      level: Value(level),
      title: Value(title),
      description: Value(description),
      capabilitiesJson: Value(capabilitiesJson),
      estimatedHours: Value(estimatedHours),
      status: Value(status),
      alternativePathsJson: Value(alternativePathsJson),
    );
  }

  factory LearningMilestoneRowData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LearningMilestoneRowData(
      id: serializer.fromJson<String>(json['id']),
      journeyId: serializer.fromJson<String>(json['journeyId']),
      level: serializer.fromJson<String>(json['level']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      capabilitiesJson: serializer.fromJson<String>(json['capabilitiesJson']),
      estimatedHours: serializer.fromJson<double>(json['estimatedHours']),
      status: serializer.fromJson<String>(json['status']),
      alternativePathsJson: serializer.fromJson<String>(
        json['alternativePathsJson'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'journeyId': serializer.toJson<String>(journeyId),
      'level': serializer.toJson<String>(level),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'capabilitiesJson': serializer.toJson<String>(capabilitiesJson),
      'estimatedHours': serializer.toJson<double>(estimatedHours),
      'status': serializer.toJson<String>(status),
      'alternativePathsJson': serializer.toJson<String>(alternativePathsJson),
    };
  }

  LearningMilestoneRowData copyWith({
    String? id,
    String? journeyId,
    String? level,
    String? title,
    String? description,
    String? capabilitiesJson,
    double? estimatedHours,
    String? status,
    String? alternativePathsJson,
  }) => LearningMilestoneRowData(
    id: id ?? this.id,
    journeyId: journeyId ?? this.journeyId,
    level: level ?? this.level,
    title: title ?? this.title,
    description: description ?? this.description,
    capabilitiesJson: capabilitiesJson ?? this.capabilitiesJson,
    estimatedHours: estimatedHours ?? this.estimatedHours,
    status: status ?? this.status,
    alternativePathsJson: alternativePathsJson ?? this.alternativePathsJson,
  );
  LearningMilestoneRowData copyWithCompanion(LearningMilestonesCompanion data) {
    return LearningMilestoneRowData(
      id: data.id.present ? data.id.value : this.id,
      journeyId: data.journeyId.present ? data.journeyId.value : this.journeyId,
      level: data.level.present ? data.level.value : this.level,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      capabilitiesJson: data.capabilitiesJson.present
          ? data.capabilitiesJson.value
          : this.capabilitiesJson,
      estimatedHours: data.estimatedHours.present
          ? data.estimatedHours.value
          : this.estimatedHours,
      status: data.status.present ? data.status.value : this.status,
      alternativePathsJson: data.alternativePathsJson.present
          ? data.alternativePathsJson.value
          : this.alternativePathsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LearningMilestoneRowData(')
          ..write('id: $id, ')
          ..write('journeyId: $journeyId, ')
          ..write('level: $level, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('capabilitiesJson: $capabilitiesJson, ')
          ..write('estimatedHours: $estimatedHours, ')
          ..write('status: $status, ')
          ..write('alternativePathsJson: $alternativePathsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    journeyId,
    level,
    title,
    description,
    capabilitiesJson,
    estimatedHours,
    status,
    alternativePathsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LearningMilestoneRowData &&
          other.id == this.id &&
          other.journeyId == this.journeyId &&
          other.level == this.level &&
          other.title == this.title &&
          other.description == this.description &&
          other.capabilitiesJson == this.capabilitiesJson &&
          other.estimatedHours == this.estimatedHours &&
          other.status == this.status &&
          other.alternativePathsJson == this.alternativePathsJson);
}

class LearningMilestonesCompanion
    extends UpdateCompanion<LearningMilestoneRowData> {
  final Value<String> id;
  final Value<String> journeyId;
  final Value<String> level;
  final Value<String> title;
  final Value<String> description;
  final Value<String> capabilitiesJson;
  final Value<double> estimatedHours;
  final Value<String> status;
  final Value<String> alternativePathsJson;
  final Value<int> rowid;
  const LearningMilestonesCompanion({
    this.id = const Value.absent(),
    this.journeyId = const Value.absent(),
    this.level = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.capabilitiesJson = const Value.absent(),
    this.estimatedHours = const Value.absent(),
    this.status = const Value.absent(),
    this.alternativePathsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LearningMilestonesCompanion.insert({
    required String id,
    required String journeyId,
    required String level,
    required String title,
    this.description = const Value.absent(),
    this.capabilitiesJson = const Value.absent(),
    this.estimatedHours = const Value.absent(),
    this.status = const Value.absent(),
    this.alternativePathsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       journeyId = Value(journeyId),
       level = Value(level),
       title = Value(title);
  static Insertable<LearningMilestoneRowData> custom({
    Expression<String>? id,
    Expression<String>? journeyId,
    Expression<String>? level,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? capabilitiesJson,
    Expression<double>? estimatedHours,
    Expression<String>? status,
    Expression<String>? alternativePathsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (journeyId != null) 'journey_id': journeyId,
      if (level != null) 'level': level,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (capabilitiesJson != null) 'capabilities_json': capabilitiesJson,
      if (estimatedHours != null) 'estimated_hours': estimatedHours,
      if (status != null) 'status': status,
      if (alternativePathsJson != null)
        'alternative_paths_json': alternativePathsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LearningMilestonesCompanion copyWith({
    Value<String>? id,
    Value<String>? journeyId,
    Value<String>? level,
    Value<String>? title,
    Value<String>? description,
    Value<String>? capabilitiesJson,
    Value<double>? estimatedHours,
    Value<String>? status,
    Value<String>? alternativePathsJson,
    Value<int>? rowid,
  }) {
    return LearningMilestonesCompanion(
      id: id ?? this.id,
      journeyId: journeyId ?? this.journeyId,
      level: level ?? this.level,
      title: title ?? this.title,
      description: description ?? this.description,
      capabilitiesJson: capabilitiesJson ?? this.capabilitiesJson,
      estimatedHours: estimatedHours ?? this.estimatedHours,
      status: status ?? this.status,
      alternativePathsJson: alternativePathsJson ?? this.alternativePathsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (journeyId.present) {
      map['journey_id'] = Variable<String>(journeyId.value);
    }
    if (level.present) {
      map['level'] = Variable<String>(level.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (capabilitiesJson.present) {
      map['capabilities_json'] = Variable<String>(capabilitiesJson.value);
    }
    if (estimatedHours.present) {
      map['estimated_hours'] = Variable<double>(estimatedHours.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (alternativePathsJson.present) {
      map['alternative_paths_json'] = Variable<String>(
        alternativePathsJson.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LearningMilestonesCompanion(')
          ..write('id: $id, ')
          ..write('journeyId: $journeyId, ')
          ..write('level: $level, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('capabilitiesJson: $capabilitiesJson, ')
          ..write('estimatedHours: $estimatedHours, ')
          ..write('status: $status, ')
          ..write('alternativePathsJson: $alternativePathsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LearningSessionsTable extends LearningSessions
    with TableInfo<$LearningSessionsTable, LearningSessionRowData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LearningSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _journeyIdMeta = const VerificationMeta(
    'journeyId',
  );
  @override
  late final GeneratedColumn<String> journeyId = GeneratedColumn<String>(
    'journey_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES learning_journeys (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _milestoneIdMeta = const VerificationMeta(
    'milestoneId',
  );
  @override
  late final GeneratedColumn<String> milestoneId = GeneratedColumn<String>(
    'milestone_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES learning_milestones (id)',
    ),
  );
  static const VerificationMeta _topicIdMeta = const VerificationMeta(
    'topicId',
  );
  @override
  late final GeneratedColumn<String> topicId = GeneratedColumn<String>(
    'topic_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES topics (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _goalMeta = const VerificationMeta('goal');
  @override
  late final GeneratedColumn<String> goal = GeneratedColumn<String>(
    'goal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('overview'),
  );
  static const VerificationMeta _timeBudgetMinutesMeta = const VerificationMeta(
    'timeBudgetMinutes',
  );
  @override
  late final GeneratedColumn<int> timeBudgetMinutes = GeneratedColumn<int>(
    'time_budget_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(60),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
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
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _curriculumJsonMeta = const VerificationMeta(
    'curriculumJson',
  );
  @override
  late final GeneratedColumn<String> curriculumJson = GeneratedColumn<String>(
    'curriculum_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _currentIndexMeta = const VerificationMeta(
    'currentIndex',
  );
  @override
  late final GeneratedColumn<int> currentIndex = GeneratedColumn<int>(
    'current_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _activityJsonMeta = const VerificationMeta(
    'activityJson',
  );
  @override
  late final GeneratedColumn<String> activityJson = GeneratedColumn<String>(
    'activity_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _currentActivityStepMeta =
      const VerificationMeta('currentActivityStep');
  @override
  late final GeneratedColumn<int> currentActivityStep = GeneratedColumn<int>(
    'current_activity_step',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    journeyId,
    milestoneId,
    topicId,
    goal,
    timeBudgetMinutes,
    startedAt,
    completedAt,
    status,
    curriculumJson,
    currentIndex,
    activityJson,
    currentActivityStep,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'learning_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<LearningSessionRowData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('journey_id')) {
      context.handle(
        _journeyIdMeta,
        journeyId.isAcceptableOrUnknown(data['journey_id']!, _journeyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_journeyIdMeta);
    }
    if (data.containsKey('milestone_id')) {
      context.handle(
        _milestoneIdMeta,
        milestoneId.isAcceptableOrUnknown(
          data['milestone_id']!,
          _milestoneIdMeta,
        ),
      );
    }
    if (data.containsKey('topic_id')) {
      context.handle(
        _topicIdMeta,
        topicId.isAcceptableOrUnknown(data['topic_id']!, _topicIdMeta),
      );
    } else if (isInserting) {
      context.missing(_topicIdMeta);
    }
    if (data.containsKey('goal')) {
      context.handle(
        _goalMeta,
        goal.isAcceptableOrUnknown(data['goal']!, _goalMeta),
      );
    }
    if (data.containsKey('time_budget_minutes')) {
      context.handle(
        _timeBudgetMinutesMeta,
        timeBudgetMinutes.isAcceptableOrUnknown(
          data['time_budget_minutes']!,
          _timeBudgetMinutesMeta,
        ),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('curriculum_json')) {
      context.handle(
        _curriculumJsonMeta,
        curriculumJson.isAcceptableOrUnknown(
          data['curriculum_json']!,
          _curriculumJsonMeta,
        ),
      );
    }
    if (data.containsKey('current_index')) {
      context.handle(
        _currentIndexMeta,
        currentIndex.isAcceptableOrUnknown(
          data['current_index']!,
          _currentIndexMeta,
        ),
      );
    }
    if (data.containsKey('activity_json')) {
      context.handle(
        _activityJsonMeta,
        activityJson.isAcceptableOrUnknown(
          data['activity_json']!,
          _activityJsonMeta,
        ),
      );
    }
    if (data.containsKey('current_activity_step')) {
      context.handle(
        _currentActivityStepMeta,
        currentActivityStep.isAcceptableOrUnknown(
          data['current_activity_step']!,
          _currentActivityStepMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LearningSessionRowData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LearningSessionRowData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      journeyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}journey_id'],
      )!,
      milestoneId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}milestone_id'],
      ),
      topicId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic_id'],
      )!,
      goal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}goal'],
      )!,
      timeBudgetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_budget_minutes'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      curriculumJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}curriculum_json'],
      )!,
      currentIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_index'],
      )!,
      activityJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_json'],
      )!,
      currentActivityStep: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_activity_step'],
      )!,
    );
  }

  @override
  $LearningSessionsTable createAlias(String alias) {
    return $LearningSessionsTable(attachedDatabase, alias);
  }
}

class LearningSessionRowData extends DataClass
    implements Insertable<LearningSessionRowData> {
  final String id;
  final String journeyId;
  final String? milestoneId;
  final String topicId;
  final String goal;
  final int timeBudgetMinutes;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String status;
  final String curriculumJson;
  final int currentIndex;
  final String activityJson;
  final int currentActivityStep;
  const LearningSessionRowData({
    required this.id,
    required this.journeyId,
    this.milestoneId,
    required this.topicId,
    required this.goal,
    required this.timeBudgetMinutes,
    required this.startedAt,
    this.completedAt,
    required this.status,
    required this.curriculumJson,
    required this.currentIndex,
    required this.activityJson,
    required this.currentActivityStep,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['journey_id'] = Variable<String>(journeyId);
    if (!nullToAbsent || milestoneId != null) {
      map['milestone_id'] = Variable<String>(milestoneId);
    }
    map['topic_id'] = Variable<String>(topicId);
    map['goal'] = Variable<String>(goal);
    map['time_budget_minutes'] = Variable<int>(timeBudgetMinutes);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    map['status'] = Variable<String>(status);
    map['curriculum_json'] = Variable<String>(curriculumJson);
    map['current_index'] = Variable<int>(currentIndex);
    map['activity_json'] = Variable<String>(activityJson);
    map['current_activity_step'] = Variable<int>(currentActivityStep);
    return map;
  }

  LearningSessionsCompanion toCompanion(bool nullToAbsent) {
    return LearningSessionsCompanion(
      id: Value(id),
      journeyId: Value(journeyId),
      milestoneId: milestoneId == null && nullToAbsent
          ? const Value.absent()
          : Value(milestoneId),
      topicId: Value(topicId),
      goal: Value(goal),
      timeBudgetMinutes: Value(timeBudgetMinutes),
      startedAt: Value(startedAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      status: Value(status),
      curriculumJson: Value(curriculumJson),
      currentIndex: Value(currentIndex),
      activityJson: Value(activityJson),
      currentActivityStep: Value(currentActivityStep),
    );
  }

  factory LearningSessionRowData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LearningSessionRowData(
      id: serializer.fromJson<String>(json['id']),
      journeyId: serializer.fromJson<String>(json['journeyId']),
      milestoneId: serializer.fromJson<String?>(json['milestoneId']),
      topicId: serializer.fromJson<String>(json['topicId']),
      goal: serializer.fromJson<String>(json['goal']),
      timeBudgetMinutes: serializer.fromJson<int>(json['timeBudgetMinutes']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      status: serializer.fromJson<String>(json['status']),
      curriculumJson: serializer.fromJson<String>(json['curriculumJson']),
      currentIndex: serializer.fromJson<int>(json['currentIndex']),
      activityJson: serializer.fromJson<String>(json['activityJson']),
      currentActivityStep: serializer.fromJson<int>(
        json['currentActivityStep'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'journeyId': serializer.toJson<String>(journeyId),
      'milestoneId': serializer.toJson<String?>(milestoneId),
      'topicId': serializer.toJson<String>(topicId),
      'goal': serializer.toJson<String>(goal),
      'timeBudgetMinutes': serializer.toJson<int>(timeBudgetMinutes),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'status': serializer.toJson<String>(status),
      'curriculumJson': serializer.toJson<String>(curriculumJson),
      'currentIndex': serializer.toJson<int>(currentIndex),
      'activityJson': serializer.toJson<String>(activityJson),
      'currentActivityStep': serializer.toJson<int>(currentActivityStep),
    };
  }

  LearningSessionRowData copyWith({
    String? id,
    String? journeyId,
    Value<String?> milestoneId = const Value.absent(),
    String? topicId,
    String? goal,
    int? timeBudgetMinutes,
    DateTime? startedAt,
    Value<DateTime?> completedAt = const Value.absent(),
    String? status,
    String? curriculumJson,
    int? currentIndex,
    String? activityJson,
    int? currentActivityStep,
  }) => LearningSessionRowData(
    id: id ?? this.id,
    journeyId: journeyId ?? this.journeyId,
    milestoneId: milestoneId.present ? milestoneId.value : this.milestoneId,
    topicId: topicId ?? this.topicId,
    goal: goal ?? this.goal,
    timeBudgetMinutes: timeBudgetMinutes ?? this.timeBudgetMinutes,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    status: status ?? this.status,
    curriculumJson: curriculumJson ?? this.curriculumJson,
    currentIndex: currentIndex ?? this.currentIndex,
    activityJson: activityJson ?? this.activityJson,
    currentActivityStep: currentActivityStep ?? this.currentActivityStep,
  );
  LearningSessionRowData copyWithCompanion(LearningSessionsCompanion data) {
    return LearningSessionRowData(
      id: data.id.present ? data.id.value : this.id,
      journeyId: data.journeyId.present ? data.journeyId.value : this.journeyId,
      milestoneId: data.milestoneId.present
          ? data.milestoneId.value
          : this.milestoneId,
      topicId: data.topicId.present ? data.topicId.value : this.topicId,
      goal: data.goal.present ? data.goal.value : this.goal,
      timeBudgetMinutes: data.timeBudgetMinutes.present
          ? data.timeBudgetMinutes.value
          : this.timeBudgetMinutes,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      status: data.status.present ? data.status.value : this.status,
      curriculumJson: data.curriculumJson.present
          ? data.curriculumJson.value
          : this.curriculumJson,
      currentIndex: data.currentIndex.present
          ? data.currentIndex.value
          : this.currentIndex,
      activityJson: data.activityJson.present
          ? data.activityJson.value
          : this.activityJson,
      currentActivityStep: data.currentActivityStep.present
          ? data.currentActivityStep.value
          : this.currentActivityStep,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LearningSessionRowData(')
          ..write('id: $id, ')
          ..write('journeyId: $journeyId, ')
          ..write('milestoneId: $milestoneId, ')
          ..write('topicId: $topicId, ')
          ..write('goal: $goal, ')
          ..write('timeBudgetMinutes: $timeBudgetMinutes, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('status: $status, ')
          ..write('curriculumJson: $curriculumJson, ')
          ..write('currentIndex: $currentIndex, ')
          ..write('activityJson: $activityJson, ')
          ..write('currentActivityStep: $currentActivityStep')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    journeyId,
    milestoneId,
    topicId,
    goal,
    timeBudgetMinutes,
    startedAt,
    completedAt,
    status,
    curriculumJson,
    currentIndex,
    activityJson,
    currentActivityStep,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LearningSessionRowData &&
          other.id == this.id &&
          other.journeyId == this.journeyId &&
          other.milestoneId == this.milestoneId &&
          other.topicId == this.topicId &&
          other.goal == this.goal &&
          other.timeBudgetMinutes == this.timeBudgetMinutes &&
          other.startedAt == this.startedAt &&
          other.completedAt == this.completedAt &&
          other.status == this.status &&
          other.curriculumJson == this.curriculumJson &&
          other.currentIndex == this.currentIndex &&
          other.activityJson == this.activityJson &&
          other.currentActivityStep == this.currentActivityStep);
}

class LearningSessionsCompanion
    extends UpdateCompanion<LearningSessionRowData> {
  final Value<String> id;
  final Value<String> journeyId;
  final Value<String?> milestoneId;
  final Value<String> topicId;
  final Value<String> goal;
  final Value<int> timeBudgetMinutes;
  final Value<DateTime> startedAt;
  final Value<DateTime?> completedAt;
  final Value<String> status;
  final Value<String> curriculumJson;
  final Value<int> currentIndex;
  final Value<String> activityJson;
  final Value<int> currentActivityStep;
  final Value<int> rowid;
  const LearningSessionsCompanion({
    this.id = const Value.absent(),
    this.journeyId = const Value.absent(),
    this.milestoneId = const Value.absent(),
    this.topicId = const Value.absent(),
    this.goal = const Value.absent(),
    this.timeBudgetMinutes = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.curriculumJson = const Value.absent(),
    this.currentIndex = const Value.absent(),
    this.activityJson = const Value.absent(),
    this.currentActivityStep = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LearningSessionsCompanion.insert({
    required String id,
    required String journeyId,
    this.milestoneId = const Value.absent(),
    required String topicId,
    this.goal = const Value.absent(),
    this.timeBudgetMinutes = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.curriculumJson = const Value.absent(),
    this.currentIndex = const Value.absent(),
    this.activityJson = const Value.absent(),
    this.currentActivityStep = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       journeyId = Value(journeyId),
       topicId = Value(topicId);
  static Insertable<LearningSessionRowData> custom({
    Expression<String>? id,
    Expression<String>? journeyId,
    Expression<String>? milestoneId,
    Expression<String>? topicId,
    Expression<String>? goal,
    Expression<int>? timeBudgetMinutes,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? completedAt,
    Expression<String>? status,
    Expression<String>? curriculumJson,
    Expression<int>? currentIndex,
    Expression<String>? activityJson,
    Expression<int>? currentActivityStep,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (journeyId != null) 'journey_id': journeyId,
      if (milestoneId != null) 'milestone_id': milestoneId,
      if (topicId != null) 'topic_id': topicId,
      if (goal != null) 'goal': goal,
      if (timeBudgetMinutes != null) 'time_budget_minutes': timeBudgetMinutes,
      if (startedAt != null) 'started_at': startedAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (status != null) 'status': status,
      if (curriculumJson != null) 'curriculum_json': curriculumJson,
      if (currentIndex != null) 'current_index': currentIndex,
      if (activityJson != null) 'activity_json': activityJson,
      if (currentActivityStep != null)
        'current_activity_step': currentActivityStep,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LearningSessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? journeyId,
    Value<String?>? milestoneId,
    Value<String>? topicId,
    Value<String>? goal,
    Value<int>? timeBudgetMinutes,
    Value<DateTime>? startedAt,
    Value<DateTime?>? completedAt,
    Value<String>? status,
    Value<String>? curriculumJson,
    Value<int>? currentIndex,
    Value<String>? activityJson,
    Value<int>? currentActivityStep,
    Value<int>? rowid,
  }) {
    return LearningSessionsCompanion(
      id: id ?? this.id,
      journeyId: journeyId ?? this.journeyId,
      milestoneId: milestoneId ?? this.milestoneId,
      topicId: topicId ?? this.topicId,
      goal: goal ?? this.goal,
      timeBudgetMinutes: timeBudgetMinutes ?? this.timeBudgetMinutes,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      status: status ?? this.status,
      curriculumJson: curriculumJson ?? this.curriculumJson,
      currentIndex: currentIndex ?? this.currentIndex,
      activityJson: activityJson ?? this.activityJson,
      currentActivityStep: currentActivityStep ?? this.currentActivityStep,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (journeyId.present) {
      map['journey_id'] = Variable<String>(journeyId.value);
    }
    if (milestoneId.present) {
      map['milestone_id'] = Variable<String>(milestoneId.value);
    }
    if (topicId.present) {
      map['topic_id'] = Variable<String>(topicId.value);
    }
    if (goal.present) {
      map['goal'] = Variable<String>(goal.value);
    }
    if (timeBudgetMinutes.present) {
      map['time_budget_minutes'] = Variable<int>(timeBudgetMinutes.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (curriculumJson.present) {
      map['curriculum_json'] = Variable<String>(curriculumJson.value);
    }
    if (currentIndex.present) {
      map['current_index'] = Variable<int>(currentIndex.value);
    }
    if (activityJson.present) {
      map['activity_json'] = Variable<String>(activityJson.value);
    }
    if (currentActivityStep.present) {
      map['current_activity_step'] = Variable<int>(currentActivityStep.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LearningSessionsCompanion(')
          ..write('id: $id, ')
          ..write('journeyId: $journeyId, ')
          ..write('milestoneId: $milestoneId, ')
          ..write('topicId: $topicId, ')
          ..write('goal: $goal, ')
          ..write('timeBudgetMinutes: $timeBudgetMinutes, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('status: $status, ')
          ..write('curriculumJson: $curriculumJson, ')
          ..write('currentIndex: $currentIndex, ')
          ..write('activityJson: $activityJson, ')
          ..write('currentActivityStep: $currentActivityStep, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LearningEventsTable extends LearningEvents
    with TableInfo<$LearningEventsTable, LearningEventRowData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LearningEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES learning_sessions (id) ON DELETE CASCADE',
    ),
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
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nodeIdMeta = const VerificationMeta('nodeId');
  @override
  late final GeneratedColumn<String> nodeId = GeneratedColumn<String>(
    'node_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dataJsonMeta = const VerificationMeta(
    'dataJson',
  );
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
    'data_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    timestamp,
    type,
    nodeId,
    dataJson,
    durationMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'learning_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<LearningEventRowData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('node_id')) {
      context.handle(
        _nodeIdMeta,
        nodeId.isAcceptableOrUnknown(data['node_id']!, _nodeIdMeta),
      );
    }
    if (data.containsKey('data_json')) {
      context.handle(
        _dataJsonMeta,
        dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LearningEventRowData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LearningEventRowData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      nodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_id'],
      ),
      dataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_json'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
    );
  }

  @override
  $LearningEventsTable createAlias(String alias) {
    return $LearningEventsTable(attachedDatabase, alias);
  }
}

class LearningEventRowData extends DataClass
    implements Insertable<LearningEventRowData> {
  final String id;
  final String sessionId;
  final DateTime timestamp;
  final String type;
  final String? nodeId;
  final String dataJson;
  final int durationMs;
  const LearningEventRowData({
    required this.id,
    required this.sessionId,
    required this.timestamp,
    required this.type,
    this.nodeId,
    required this.dataJson,
    required this.durationMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || nodeId != null) {
      map['node_id'] = Variable<String>(nodeId);
    }
    map['data_json'] = Variable<String>(dataJson);
    map['duration_ms'] = Variable<int>(durationMs);
    return map;
  }

  LearningEventsCompanion toCompanion(bool nullToAbsent) {
    return LearningEventsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      timestamp: Value(timestamp),
      type: Value(type),
      nodeId: nodeId == null && nullToAbsent
          ? const Value.absent()
          : Value(nodeId),
      dataJson: Value(dataJson),
      durationMs: Value(durationMs),
    );
  }

  factory LearningEventRowData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LearningEventRowData(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      type: serializer.fromJson<String>(json['type']),
      nodeId: serializer.fromJson<String?>(json['nodeId']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'type': serializer.toJson<String>(type),
      'nodeId': serializer.toJson<String?>(nodeId),
      'dataJson': serializer.toJson<String>(dataJson),
      'durationMs': serializer.toJson<int>(durationMs),
    };
  }

  LearningEventRowData copyWith({
    String? id,
    String? sessionId,
    DateTime? timestamp,
    String? type,
    Value<String?> nodeId = const Value.absent(),
    String? dataJson,
    int? durationMs,
  }) => LearningEventRowData(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    timestamp: timestamp ?? this.timestamp,
    type: type ?? this.type,
    nodeId: nodeId.present ? nodeId.value : this.nodeId,
    dataJson: dataJson ?? this.dataJson,
    durationMs: durationMs ?? this.durationMs,
  );
  LearningEventRowData copyWithCompanion(LearningEventsCompanion data) {
    return LearningEventRowData(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      type: data.type.present ? data.type.value : this.type,
      nodeId: data.nodeId.present ? data.nodeId.value : this.nodeId,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LearningEventRowData(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('timestamp: $timestamp, ')
          ..write('type: $type, ')
          ..write('nodeId: $nodeId, ')
          ..write('dataJson: $dataJson, ')
          ..write('durationMs: $durationMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, sessionId, timestamp, type, nodeId, dataJson, durationMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LearningEventRowData &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.timestamp == this.timestamp &&
          other.type == this.type &&
          other.nodeId == this.nodeId &&
          other.dataJson == this.dataJson &&
          other.durationMs == this.durationMs);
}

class LearningEventsCompanion extends UpdateCompanion<LearningEventRowData> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<DateTime> timestamp;
  final Value<String> type;
  final Value<String?> nodeId;
  final Value<String> dataJson;
  final Value<int> durationMs;
  final Value<int> rowid;
  const LearningEventsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.type = const Value.absent(),
    this.nodeId = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LearningEventsCompanion.insert({
    required String id,
    required String sessionId,
    this.timestamp = const Value.absent(),
    required String type,
    this.nodeId = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       type = Value(type);
  static Insertable<LearningEventRowData> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<DateTime>? timestamp,
    Expression<String>? type,
    Expression<String>? nodeId,
    Expression<String>? dataJson,
    Expression<int>? durationMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (timestamp != null) 'timestamp': timestamp,
      if (type != null) 'type': type,
      if (nodeId != null) 'node_id': nodeId,
      if (dataJson != null) 'data_json': dataJson,
      if (durationMs != null) 'duration_ms': durationMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LearningEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<DateTime>? timestamp,
    Value<String>? type,
    Value<String?>? nodeId,
    Value<String>? dataJson,
    Value<int>? durationMs,
    Value<int>? rowid,
  }) {
    return LearningEventsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      nodeId: nodeId ?? this.nodeId,
      dataJson: dataJson ?? this.dataJson,
      durationMs: durationMs ?? this.durationMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (nodeId.present) {
      map['node_id'] = Variable<String>(nodeId.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LearningEventsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('timestamp: $timestamp, ')
          ..write('type: $type, ')
          ..write('nodeId: $nodeId, ')
          ..write('dataJson: $dataJson, ')
          ..write('durationMs: $durationMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LearnerModelsTable extends LearnerModels
    with TableInfo<$LearnerModelsTable, LearnerModelRowData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LearnerModelsTable(this.attachedDatabase, [this._alias]);
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
    requiredDuringInsert: false,
    defaultValue: const Constant('default'),
  );
  static const VerificationMeta _topicIdMeta = const VerificationMeta(
    'topicId',
  );
  @override
  late final GeneratedColumn<String> topicId = GeneratedColumn<String>(
    'topic_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES topics (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _overallLevelMeta = const VerificationMeta(
    'overallLevel',
  );
  @override
  late final GeneratedColumn<String> overallLevel = GeneratedColumn<String>(
    'overall_level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('awareness'),
  );
  static const VerificationMeta _conceptMasteriesJsonMeta =
      const VerificationMeta('conceptMasteriesJson');
  @override
  late final GeneratedColumn<String> conceptMasteriesJson =
      GeneratedColumn<String>(
        'concept_masteries_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
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
  static const VerificationMeta _initialOverallLevelMeta =
      const VerificationMeta('initialOverallLevel');
  @override
  late final GeneratedColumn<String> initialOverallLevel =
      GeneratedColumn<String>(
        'initial_overall_level',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('awareness'),
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    topicId,
    overallLevel,
    conceptMasteriesJson,
    updatedAt,
    initialOverallLevel,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'learner_models';
  @override
  VerificationContext validateIntegrity(
    Insertable<LearnerModelRowData> instance, {
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
    }
    if (data.containsKey('topic_id')) {
      context.handle(
        _topicIdMeta,
        topicId.isAcceptableOrUnknown(data['topic_id']!, _topicIdMeta),
      );
    } else if (isInserting) {
      context.missing(_topicIdMeta);
    }
    if (data.containsKey('overall_level')) {
      context.handle(
        _overallLevelMeta,
        overallLevel.isAcceptableOrUnknown(
          data['overall_level']!,
          _overallLevelMeta,
        ),
      );
    }
    if (data.containsKey('concept_masteries_json')) {
      context.handle(
        _conceptMasteriesJsonMeta,
        conceptMasteriesJson.isAcceptableOrUnknown(
          data['concept_masteries_json']!,
          _conceptMasteriesJsonMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('initial_overall_level')) {
      context.handle(
        _initialOverallLevelMeta,
        initialOverallLevel.isAcceptableOrUnknown(
          data['initial_overall_level']!,
          _initialOverallLevelMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {userId, topicId},
  ];
  @override
  LearnerModelRowData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LearnerModelRowData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      topicId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic_id'],
      )!,
      overallLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}overall_level'],
      )!,
      conceptMasteriesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}concept_masteries_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      initialOverallLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}initial_overall_level'],
      )!,
    );
  }

  @override
  $LearnerModelsTable createAlias(String alias) {
    return $LearnerModelsTable(attachedDatabase, alias);
  }
}

class LearnerModelRowData extends DataClass
    implements Insertable<LearnerModelRowData> {
  final String id;
  final String userId;
  final String topicId;
  final String overallLevel;
  final String conceptMasteriesJson;
  final DateTime updatedAt;
  final String initialOverallLevel;
  const LearnerModelRowData({
    required this.id,
    required this.userId,
    required this.topicId,
    required this.overallLevel,
    required this.conceptMasteriesJson,
    required this.updatedAt,
    required this.initialOverallLevel,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['topic_id'] = Variable<String>(topicId);
    map['overall_level'] = Variable<String>(overallLevel);
    map['concept_masteries_json'] = Variable<String>(conceptMasteriesJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['initial_overall_level'] = Variable<String>(initialOverallLevel);
    return map;
  }

  LearnerModelsCompanion toCompanion(bool nullToAbsent) {
    return LearnerModelsCompanion(
      id: Value(id),
      userId: Value(userId),
      topicId: Value(topicId),
      overallLevel: Value(overallLevel),
      conceptMasteriesJson: Value(conceptMasteriesJson),
      updatedAt: Value(updatedAt),
      initialOverallLevel: Value(initialOverallLevel),
    );
  }

  factory LearnerModelRowData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LearnerModelRowData(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      topicId: serializer.fromJson<String>(json['topicId']),
      overallLevel: serializer.fromJson<String>(json['overallLevel']),
      conceptMasteriesJson: serializer.fromJson<String>(
        json['conceptMasteriesJson'],
      ),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      initialOverallLevel: serializer.fromJson<String>(
        json['initialOverallLevel'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'topicId': serializer.toJson<String>(topicId),
      'overallLevel': serializer.toJson<String>(overallLevel),
      'conceptMasteriesJson': serializer.toJson<String>(conceptMasteriesJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'initialOverallLevel': serializer.toJson<String>(initialOverallLevel),
    };
  }

  LearnerModelRowData copyWith({
    String? id,
    String? userId,
    String? topicId,
    String? overallLevel,
    String? conceptMasteriesJson,
    DateTime? updatedAt,
    String? initialOverallLevel,
  }) => LearnerModelRowData(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    topicId: topicId ?? this.topicId,
    overallLevel: overallLevel ?? this.overallLevel,
    conceptMasteriesJson: conceptMasteriesJson ?? this.conceptMasteriesJson,
    updatedAt: updatedAt ?? this.updatedAt,
    initialOverallLevel: initialOverallLevel ?? this.initialOverallLevel,
  );
  LearnerModelRowData copyWithCompanion(LearnerModelsCompanion data) {
    return LearnerModelRowData(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      topicId: data.topicId.present ? data.topicId.value : this.topicId,
      overallLevel: data.overallLevel.present
          ? data.overallLevel.value
          : this.overallLevel,
      conceptMasteriesJson: data.conceptMasteriesJson.present
          ? data.conceptMasteriesJson.value
          : this.conceptMasteriesJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      initialOverallLevel: data.initialOverallLevel.present
          ? data.initialOverallLevel.value
          : this.initialOverallLevel,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LearnerModelRowData(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('topicId: $topicId, ')
          ..write('overallLevel: $overallLevel, ')
          ..write('conceptMasteriesJson: $conceptMasteriesJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('initialOverallLevel: $initialOverallLevel')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    topicId,
    overallLevel,
    conceptMasteriesJson,
    updatedAt,
    initialOverallLevel,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LearnerModelRowData &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.topicId == this.topicId &&
          other.overallLevel == this.overallLevel &&
          other.conceptMasteriesJson == this.conceptMasteriesJson &&
          other.updatedAt == this.updatedAt &&
          other.initialOverallLevel == this.initialOverallLevel);
}

class LearnerModelsCompanion extends UpdateCompanion<LearnerModelRowData> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> topicId;
  final Value<String> overallLevel;
  final Value<String> conceptMasteriesJson;
  final Value<DateTime> updatedAt;
  final Value<String> initialOverallLevel;
  final Value<int> rowid;
  const LearnerModelsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.topicId = const Value.absent(),
    this.overallLevel = const Value.absent(),
    this.conceptMasteriesJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.initialOverallLevel = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LearnerModelsCompanion.insert({
    required String id,
    this.userId = const Value.absent(),
    required String topicId,
    this.overallLevel = const Value.absent(),
    this.conceptMasteriesJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.initialOverallLevel = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       topicId = Value(topicId);
  static Insertable<LearnerModelRowData> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? topicId,
    Expression<String>? overallLevel,
    Expression<String>? conceptMasteriesJson,
    Expression<DateTime>? updatedAt,
    Expression<String>? initialOverallLevel,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (topicId != null) 'topic_id': topicId,
      if (overallLevel != null) 'overall_level': overallLevel,
      if (conceptMasteriesJson != null)
        'concept_masteries_json': conceptMasteriesJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (initialOverallLevel != null)
        'initial_overall_level': initialOverallLevel,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LearnerModelsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? topicId,
    Value<String>? overallLevel,
    Value<String>? conceptMasteriesJson,
    Value<DateTime>? updatedAt,
    Value<String>? initialOverallLevel,
    Value<int>? rowid,
  }) {
    return LearnerModelsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      topicId: topicId ?? this.topicId,
      overallLevel: overallLevel ?? this.overallLevel,
      conceptMasteriesJson: conceptMasteriesJson ?? this.conceptMasteriesJson,
      updatedAt: updatedAt ?? this.updatedAt,
      initialOverallLevel: initialOverallLevel ?? this.initialOverallLevel,
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
    if (topicId.present) {
      map['topic_id'] = Variable<String>(topicId.value);
    }
    if (overallLevel.present) {
      map['overall_level'] = Variable<String>(overallLevel.value);
    }
    if (conceptMasteriesJson.present) {
      map['concept_masteries_json'] = Variable<String>(
        conceptMasteriesJson.value,
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (initialOverallLevel.present) {
      map['initial_overall_level'] = Variable<String>(
        initialOverallLevel.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LearnerModelsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('topicId: $topicId, ')
          ..write('overallLevel: $overallLevel, ')
          ..write('conceptMasteriesJson: $conceptMasteriesJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('initialOverallLevel: $initialOverallLevel, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssessmentsTable extends Assessments
    with TableInfo<$AssessmentsTable, AssessmentRowData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssessmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES learning_sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('quiz'),
  );
  static const VerificationMeta _questionsJsonMeta = const VerificationMeta(
    'questionsJson',
  );
  @override
  late final GeneratedColumn<String> questionsJson = GeneratedColumn<String>(
    'questions_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<double> score = GeneratedColumn<double>(
    'score',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    type,
    questionsJson,
    startedAt,
    completedAt,
    score,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assessments';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssessmentRowData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('questions_json')) {
      context.handle(
        _questionsJsonMeta,
        questionsJson.isAcceptableOrUnknown(
          data['questions_json']!,
          _questionsJsonMeta,
        ),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AssessmentRowData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssessmentRowData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      questionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}questions_json'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}score'],
      ),
    );
  }

  @override
  $AssessmentsTable createAlias(String alias) {
    return $AssessmentsTable(attachedDatabase, alias);
  }
}

class AssessmentRowData extends DataClass
    implements Insertable<AssessmentRowData> {
  final String id;
  final String? sessionId;
  final String type;
  final String questionsJson;
  final DateTime startedAt;
  final DateTime? completedAt;
  final double? score;
  const AssessmentRowData({
    required this.id,
    this.sessionId,
    required this.type,
    required this.questionsJson,
    required this.startedAt,
    this.completedAt,
    this.score,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    map['type'] = Variable<String>(type);
    map['questions_json'] = Variable<String>(questionsJson);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    if (!nullToAbsent || score != null) {
      map['score'] = Variable<double>(score);
    }
    return map;
  }

  AssessmentsCompanion toCompanion(bool nullToAbsent) {
    return AssessmentsCompanion(
      id: Value(id),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      type: Value(type),
      questionsJson: Value(questionsJson),
      startedAt: Value(startedAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      score: score == null && nullToAbsent
          ? const Value.absent()
          : Value(score),
    );
  }

  factory AssessmentRowData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssessmentRowData(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      type: serializer.fromJson<String>(json['type']),
      questionsJson: serializer.fromJson<String>(json['questionsJson']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      score: serializer.fromJson<double?>(json['score']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String?>(sessionId),
      'type': serializer.toJson<String>(type),
      'questionsJson': serializer.toJson<String>(questionsJson),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'score': serializer.toJson<double?>(score),
    };
  }

  AssessmentRowData copyWith({
    String? id,
    Value<String?> sessionId = const Value.absent(),
    String? type,
    String? questionsJson,
    DateTime? startedAt,
    Value<DateTime?> completedAt = const Value.absent(),
    Value<double?> score = const Value.absent(),
  }) => AssessmentRowData(
    id: id ?? this.id,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    type: type ?? this.type,
    questionsJson: questionsJson ?? this.questionsJson,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    score: score.present ? score.value : this.score,
  );
  AssessmentRowData copyWithCompanion(AssessmentsCompanion data) {
    return AssessmentRowData(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      type: data.type.present ? data.type.value : this.type,
      questionsJson: data.questionsJson.present
          ? data.questionsJson.value
          : this.questionsJson,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      score: data.score.present ? data.score.value : this.score,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssessmentRowData(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('type: $type, ')
          ..write('questionsJson: $questionsJson, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('score: $score')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    type,
    questionsJson,
    startedAt,
    completedAt,
    score,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssessmentRowData &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.type == this.type &&
          other.questionsJson == this.questionsJson &&
          other.startedAt == this.startedAt &&
          other.completedAt == this.completedAt &&
          other.score == this.score);
}

class AssessmentsCompanion extends UpdateCompanion<AssessmentRowData> {
  final Value<String> id;
  final Value<String?> sessionId;
  final Value<String> type;
  final Value<String> questionsJson;
  final Value<DateTime> startedAt;
  final Value<DateTime?> completedAt;
  final Value<double?> score;
  final Value<int> rowid;
  const AssessmentsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.type = const Value.absent(),
    this.questionsJson = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.score = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssessmentsCompanion.insert({
    required String id,
    this.sessionId = const Value.absent(),
    this.type = const Value.absent(),
    this.questionsJson = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.score = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<AssessmentRowData> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? type,
    Expression<String>? questionsJson,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? completedAt,
    Expression<double>? score,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (type != null) 'type': type,
      if (questionsJson != null) 'questions_json': questionsJson,
      if (startedAt != null) 'started_at': startedAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (score != null) 'score': score,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssessmentsCompanion copyWith({
    Value<String>? id,
    Value<String?>? sessionId,
    Value<String>? type,
    Value<String>? questionsJson,
    Value<DateTime>? startedAt,
    Value<DateTime?>? completedAt,
    Value<double?>? score,
    Value<int>? rowid,
  }) {
    return AssessmentsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      type: type ?? this.type,
      questionsJson: questionsJson ?? this.questionsJson,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      score: score ?? this.score,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (questionsJson.present) {
      map['questions_json'] = Variable<String>(questionsJson.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (score.present) {
      map['score'] = Variable<double>(score.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssessmentsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('type: $type, ')
          ..write('questionsJson: $questionsJson, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('score: $score, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssessmentAttemptsTable extends AssessmentAttempts
    with TableInfo<$AssessmentAttemptsTable, AssessmentAttemptRowData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssessmentAttemptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assessmentIdMeta = const VerificationMeta(
    'assessmentId',
  );
  @override
  late final GeneratedColumn<String> assessmentId = GeneratedColumn<String>(
    'assessment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES assessments (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _questionIdMeta = const VerificationMeta(
    'questionId',
  );
  @override
  late final GeneratedColumn<String> questionId = GeneratedColumn<String>(
    'question_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _answerMeta = const VerificationMeta('answer');
  @override
  late final GeneratedColumn<String> answer = GeneratedColumn<String>(
    'answer',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _correctMeta = const VerificationMeta(
    'correct',
  );
  @override
  late final GeneratedColumn<bool> correct = GeneratedColumn<bool>(
    'correct',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("correct" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _timeSpentMsMeta = const VerificationMeta(
    'timeSpentMs',
  );
  @override
  late final GeneratedColumn<int> timeSpentMs = GeneratedColumn<int>(
    'time_spent_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _feedbackMeta = const VerificationMeta(
    'feedback',
  );
  @override
  late final GeneratedColumn<String> feedback = GeneratedColumn<String>(
    'feedback',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    assessmentId,
    questionId,
    answer,
    correct,
    timeSpentMs,
    feedback,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assessment_attempts';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssessmentAttemptRowData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('assessment_id')) {
      context.handle(
        _assessmentIdMeta,
        assessmentId.isAcceptableOrUnknown(
          data['assessment_id']!,
          _assessmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_assessmentIdMeta);
    }
    if (data.containsKey('question_id')) {
      context.handle(
        _questionIdMeta,
        questionId.isAcceptableOrUnknown(data['question_id']!, _questionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_questionIdMeta);
    }
    if (data.containsKey('answer')) {
      context.handle(
        _answerMeta,
        answer.isAcceptableOrUnknown(data['answer']!, _answerMeta),
      );
    } else if (isInserting) {
      context.missing(_answerMeta);
    }
    if (data.containsKey('correct')) {
      context.handle(
        _correctMeta,
        correct.isAcceptableOrUnknown(data['correct']!, _correctMeta),
      );
    }
    if (data.containsKey('time_spent_ms')) {
      context.handle(
        _timeSpentMsMeta,
        timeSpentMs.isAcceptableOrUnknown(
          data['time_spent_ms']!,
          _timeSpentMsMeta,
        ),
      );
    }
    if (data.containsKey('feedback')) {
      context.handle(
        _feedbackMeta,
        feedback.isAcceptableOrUnknown(data['feedback']!, _feedbackMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AssessmentAttemptRowData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssessmentAttemptRowData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      assessmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assessment_id'],
      )!,
      questionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}question_id'],
      )!,
      answer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}answer'],
      )!,
      correct: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}correct'],
      )!,
      timeSpentMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_spent_ms'],
      )!,
      feedback: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}feedback'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AssessmentAttemptsTable createAlias(String alias) {
    return $AssessmentAttemptsTable(attachedDatabase, alias);
  }
}

class AssessmentAttemptRowData extends DataClass
    implements Insertable<AssessmentAttemptRowData> {
  final String id;
  final String assessmentId;
  final String questionId;
  final String answer;
  final bool correct;
  final int timeSpentMs;
  final String? feedback;
  final DateTime createdAt;
  const AssessmentAttemptRowData({
    required this.id,
    required this.assessmentId,
    required this.questionId,
    required this.answer,
    required this.correct,
    required this.timeSpentMs,
    this.feedback,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['assessment_id'] = Variable<String>(assessmentId);
    map['question_id'] = Variable<String>(questionId);
    map['answer'] = Variable<String>(answer);
    map['correct'] = Variable<bool>(correct);
    map['time_spent_ms'] = Variable<int>(timeSpentMs);
    if (!nullToAbsent || feedback != null) {
      map['feedback'] = Variable<String>(feedback);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AssessmentAttemptsCompanion toCompanion(bool nullToAbsent) {
    return AssessmentAttemptsCompanion(
      id: Value(id),
      assessmentId: Value(assessmentId),
      questionId: Value(questionId),
      answer: Value(answer),
      correct: Value(correct),
      timeSpentMs: Value(timeSpentMs),
      feedback: feedback == null && nullToAbsent
          ? const Value.absent()
          : Value(feedback),
      createdAt: Value(createdAt),
    );
  }

  factory AssessmentAttemptRowData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssessmentAttemptRowData(
      id: serializer.fromJson<String>(json['id']),
      assessmentId: serializer.fromJson<String>(json['assessmentId']),
      questionId: serializer.fromJson<String>(json['questionId']),
      answer: serializer.fromJson<String>(json['answer']),
      correct: serializer.fromJson<bool>(json['correct']),
      timeSpentMs: serializer.fromJson<int>(json['timeSpentMs']),
      feedback: serializer.fromJson<String?>(json['feedback']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'assessmentId': serializer.toJson<String>(assessmentId),
      'questionId': serializer.toJson<String>(questionId),
      'answer': serializer.toJson<String>(answer),
      'correct': serializer.toJson<bool>(correct),
      'timeSpentMs': serializer.toJson<int>(timeSpentMs),
      'feedback': serializer.toJson<String?>(feedback),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AssessmentAttemptRowData copyWith({
    String? id,
    String? assessmentId,
    String? questionId,
    String? answer,
    bool? correct,
    int? timeSpentMs,
    Value<String?> feedback = const Value.absent(),
    DateTime? createdAt,
  }) => AssessmentAttemptRowData(
    id: id ?? this.id,
    assessmentId: assessmentId ?? this.assessmentId,
    questionId: questionId ?? this.questionId,
    answer: answer ?? this.answer,
    correct: correct ?? this.correct,
    timeSpentMs: timeSpentMs ?? this.timeSpentMs,
    feedback: feedback.present ? feedback.value : this.feedback,
    createdAt: createdAt ?? this.createdAt,
  );
  AssessmentAttemptRowData copyWithCompanion(AssessmentAttemptsCompanion data) {
    return AssessmentAttemptRowData(
      id: data.id.present ? data.id.value : this.id,
      assessmentId: data.assessmentId.present
          ? data.assessmentId.value
          : this.assessmentId,
      questionId: data.questionId.present
          ? data.questionId.value
          : this.questionId,
      answer: data.answer.present ? data.answer.value : this.answer,
      correct: data.correct.present ? data.correct.value : this.correct,
      timeSpentMs: data.timeSpentMs.present
          ? data.timeSpentMs.value
          : this.timeSpentMs,
      feedback: data.feedback.present ? data.feedback.value : this.feedback,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssessmentAttemptRowData(')
          ..write('id: $id, ')
          ..write('assessmentId: $assessmentId, ')
          ..write('questionId: $questionId, ')
          ..write('answer: $answer, ')
          ..write('correct: $correct, ')
          ..write('timeSpentMs: $timeSpentMs, ')
          ..write('feedback: $feedback, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    assessmentId,
    questionId,
    answer,
    correct,
    timeSpentMs,
    feedback,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssessmentAttemptRowData &&
          other.id == this.id &&
          other.assessmentId == this.assessmentId &&
          other.questionId == this.questionId &&
          other.answer == this.answer &&
          other.correct == this.correct &&
          other.timeSpentMs == this.timeSpentMs &&
          other.feedback == this.feedback &&
          other.createdAt == this.createdAt);
}

class AssessmentAttemptsCompanion
    extends UpdateCompanion<AssessmentAttemptRowData> {
  final Value<String> id;
  final Value<String> assessmentId;
  final Value<String> questionId;
  final Value<String> answer;
  final Value<bool> correct;
  final Value<int> timeSpentMs;
  final Value<String?> feedback;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const AssessmentAttemptsCompanion({
    this.id = const Value.absent(),
    this.assessmentId = const Value.absent(),
    this.questionId = const Value.absent(),
    this.answer = const Value.absent(),
    this.correct = const Value.absent(),
    this.timeSpentMs = const Value.absent(),
    this.feedback = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssessmentAttemptsCompanion.insert({
    required String id,
    required String assessmentId,
    required String questionId,
    required String answer,
    this.correct = const Value.absent(),
    this.timeSpentMs = const Value.absent(),
    this.feedback = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       assessmentId = Value(assessmentId),
       questionId = Value(questionId),
       answer = Value(answer);
  static Insertable<AssessmentAttemptRowData> custom({
    Expression<String>? id,
    Expression<String>? assessmentId,
    Expression<String>? questionId,
    Expression<String>? answer,
    Expression<bool>? correct,
    Expression<int>? timeSpentMs,
    Expression<String>? feedback,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (assessmentId != null) 'assessment_id': assessmentId,
      if (questionId != null) 'question_id': questionId,
      if (answer != null) 'answer': answer,
      if (correct != null) 'correct': correct,
      if (timeSpentMs != null) 'time_spent_ms': timeSpentMs,
      if (feedback != null) 'feedback': feedback,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssessmentAttemptsCompanion copyWith({
    Value<String>? id,
    Value<String>? assessmentId,
    Value<String>? questionId,
    Value<String>? answer,
    Value<bool>? correct,
    Value<int>? timeSpentMs,
    Value<String?>? feedback,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return AssessmentAttemptsCompanion(
      id: id ?? this.id,
      assessmentId: assessmentId ?? this.assessmentId,
      questionId: questionId ?? this.questionId,
      answer: answer ?? this.answer,
      correct: correct ?? this.correct,
      timeSpentMs: timeSpentMs ?? this.timeSpentMs,
      feedback: feedback ?? this.feedback,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (assessmentId.present) {
      map['assessment_id'] = Variable<String>(assessmentId.value);
    }
    if (questionId.present) {
      map['question_id'] = Variable<String>(questionId.value);
    }
    if (answer.present) {
      map['answer'] = Variable<String>(answer.value);
    }
    if (correct.present) {
      map['correct'] = Variable<bool>(correct.value);
    }
    if (timeSpentMs.present) {
      map['time_spent_ms'] = Variable<int>(timeSpentMs.value);
    }
    if (feedback.present) {
      map['feedback'] = Variable<String>(feedback.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssessmentAttemptsCompanion(')
          ..write('id: $id, ')
          ..write('assessmentId: $assessmentId, ')
          ..write('questionId: $questionId, ')
          ..write('answer: $answer, ')
          ..write('correct: $correct, ')
          ..write('timeSpentMs: $timeSpentMs, ')
          ..write('feedback: $feedback, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$MindtreeDb extends GeneratedDatabase {
  _$MindtreeDb(QueryExecutor e) : super(e);
  $MindtreeDbManager get managers => $MindtreeDbManager(this);
  late final $TopicsTable topics = $TopicsTable(this);
  late final $KnowledgeNodesTable knowledgeNodes = $KnowledgeNodesTable(this);
  late final $LearningJourneysTable learningJourneys = $LearningJourneysTable(
    this,
  );
  late final $LearningMilestonesTable learningMilestones =
      $LearningMilestonesTable(this);
  late final $LearningSessionsTable learningSessions = $LearningSessionsTable(
    this,
  );
  late final $LearningEventsTable learningEvents = $LearningEventsTable(this);
  late final $LearnerModelsTable learnerModels = $LearnerModelsTable(this);
  late final $AssessmentsTable assessments = $AssessmentsTable(this);
  late final $AssessmentAttemptsTable assessmentAttempts =
      $AssessmentAttemptsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    topics,
    knowledgeNodes,
    learningJourneys,
    learningMilestones,
    learningSessions,
    learningEvents,
    learnerModels,
    assessments,
    assessmentAttempts,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'topics',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('knowledge_nodes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'knowledge_nodes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('knowledge_nodes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'topics',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('learning_journeys', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'learning_journeys',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('learning_milestones', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'learning_journeys',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('learning_sessions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'topics',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('learning_sessions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'learning_sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('learning_events', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'topics',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('learner_models', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'learning_sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('assessments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'assessments',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('assessment_attempts', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$TopicsTableCreateCompanionBuilder =
    TopicsCompanion Function({
      required String id,
      required String name,
      Value<String> goal,
      Value<String> targetLevel,
      Value<int> timeBudgetMinutes,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$TopicsTableUpdateCompanionBuilder =
    TopicsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> goal,
      Value<String> targetLevel,
      Value<int> timeBudgetMinutes,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$TopicsTableReferences
    extends BaseReferences<_$MindtreeDb, $TopicsTable, TopicRowData> {
  $$TopicsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$KnowledgeNodesTable, List<KnowledgeNodeRowData>>
  _knowledgeNodesRefsTable(_$MindtreeDb db) => MultiTypedResultKey.fromTable(
    db.knowledgeNodes,
    aliasName: $_aliasNameGenerator(db.topics.id, db.knowledgeNodes.topicId),
  );

  $$KnowledgeNodesTableProcessedTableManager get knowledgeNodesRefs {
    final manager = $$KnowledgeNodesTableTableManager(
      $_db,
      $_db.knowledgeNodes,
    ).filter((f) => f.topicId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_knowledgeNodesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $LearningJourneysTable,
    List<LearningJourneyRowData>
  >
  _learningJourneysRefsTable(_$MindtreeDb db) => MultiTypedResultKey.fromTable(
    db.learningJourneys,
    aliasName: $_aliasNameGenerator(db.topics.id, db.learningJourneys.topicId),
  );

  $$LearningJourneysTableProcessedTableManager get learningJourneysRefs {
    final manager = $$LearningJourneysTableTableManager(
      $_db,
      $_db.learningJourneys,
    ).filter((f) => f.topicId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _learningJourneysRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $LearningSessionsTable,
    List<LearningSessionRowData>
  >
  _learningSessionsRefsTable(_$MindtreeDb db) => MultiTypedResultKey.fromTable(
    db.learningSessions,
    aliasName: $_aliasNameGenerator(db.topics.id, db.learningSessions.topicId),
  );

  $$LearningSessionsTableProcessedTableManager get learningSessionsRefs {
    final manager = $$LearningSessionsTableTableManager(
      $_db,
      $_db.learningSessions,
    ).filter((f) => f.topicId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _learningSessionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$LearnerModelsTable, List<LearnerModelRowData>>
  _learnerModelsRefsTable(_$MindtreeDb db) => MultiTypedResultKey.fromTable(
    db.learnerModels,
    aliasName: $_aliasNameGenerator(db.topics.id, db.learnerModels.topicId),
  );

  $$LearnerModelsTableProcessedTableManager get learnerModelsRefs {
    final manager = $$LearnerModelsTableTableManager(
      $_db,
      $_db.learnerModels,
    ).filter((f) => f.topicId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_learnerModelsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TopicsTableFilterComposer extends Composer<_$MindtreeDb, $TopicsTable> {
  $$TopicsTableFilterComposer({
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

  ColumnFilters<String> get goal => $composableBuilder(
    column: $table.goal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetLevel => $composableBuilder(
    column: $table.targetLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeBudgetMinutes => $composableBuilder(
    column: $table.timeBudgetMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> knowledgeNodesRefs(
    Expression<bool> Function($$KnowledgeNodesTableFilterComposer f) f,
  ) {
    final $$KnowledgeNodesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.knowledgeNodes,
      getReferencedColumn: (t) => t.topicId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KnowledgeNodesTableFilterComposer(
            $db: $db,
            $table: $db.knowledgeNodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> learningJourneysRefs(
    Expression<bool> Function($$LearningJourneysTableFilterComposer f) f,
  ) {
    final $$LearningJourneysTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.learningJourneys,
      getReferencedColumn: (t) => t.topicId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningJourneysTableFilterComposer(
            $db: $db,
            $table: $db.learningJourneys,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> learningSessionsRefs(
    Expression<bool> Function($$LearningSessionsTableFilterComposer f) f,
  ) {
    final $$LearningSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.topicId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableFilterComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> learnerModelsRefs(
    Expression<bool> Function($$LearnerModelsTableFilterComposer f) f,
  ) {
    final $$LearnerModelsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.learnerModels,
      getReferencedColumn: (t) => t.topicId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearnerModelsTableFilterComposer(
            $db: $db,
            $table: $db.learnerModels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TopicsTableOrderingComposer
    extends Composer<_$MindtreeDb, $TopicsTable> {
  $$TopicsTableOrderingComposer({
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

  ColumnOrderings<String> get goal => $composableBuilder(
    column: $table.goal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetLevel => $composableBuilder(
    column: $table.targetLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeBudgetMinutes => $composableBuilder(
    column: $table.timeBudgetMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TopicsTableAnnotationComposer
    extends Composer<_$MindtreeDb, $TopicsTable> {
  $$TopicsTableAnnotationComposer({
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

  GeneratedColumn<String> get goal =>
      $composableBuilder(column: $table.goal, builder: (column) => column);

  GeneratedColumn<String> get targetLevel => $composableBuilder(
    column: $table.targetLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timeBudgetMinutes => $composableBuilder(
    column: $table.timeBudgetMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> knowledgeNodesRefs<T extends Object>(
    Expression<T> Function($$KnowledgeNodesTableAnnotationComposer a) f,
  ) {
    final $$KnowledgeNodesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.knowledgeNodes,
      getReferencedColumn: (t) => t.topicId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KnowledgeNodesTableAnnotationComposer(
            $db: $db,
            $table: $db.knowledgeNodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> learningJourneysRefs<T extends Object>(
    Expression<T> Function($$LearningJourneysTableAnnotationComposer a) f,
  ) {
    final $$LearningJourneysTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.learningJourneys,
      getReferencedColumn: (t) => t.topicId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningJourneysTableAnnotationComposer(
            $db: $db,
            $table: $db.learningJourneys,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> learningSessionsRefs<T extends Object>(
    Expression<T> Function($$LearningSessionsTableAnnotationComposer a) f,
  ) {
    final $$LearningSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.topicId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> learnerModelsRefs<T extends Object>(
    Expression<T> Function($$LearnerModelsTableAnnotationComposer a) f,
  ) {
    final $$LearnerModelsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.learnerModels,
      getReferencedColumn: (t) => t.topicId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearnerModelsTableAnnotationComposer(
            $db: $db,
            $table: $db.learnerModels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TopicsTableTableManager
    extends
        RootTableManager<
          _$MindtreeDb,
          $TopicsTable,
          TopicRowData,
          $$TopicsTableFilterComposer,
          $$TopicsTableOrderingComposer,
          $$TopicsTableAnnotationComposer,
          $$TopicsTableCreateCompanionBuilder,
          $$TopicsTableUpdateCompanionBuilder,
          (TopicRowData, $$TopicsTableReferences),
          TopicRowData,
          PrefetchHooks Function({
            bool knowledgeNodesRefs,
            bool learningJourneysRefs,
            bool learningSessionsRefs,
            bool learnerModelsRefs,
          })
        > {
  $$TopicsTableTableManager(_$MindtreeDb db, $TopicsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TopicsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TopicsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TopicsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> goal = const Value.absent(),
                Value<String> targetLevel = const Value.absent(),
                Value<int> timeBudgetMinutes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TopicsCompanion(
                id: id,
                name: name,
                goal: goal,
                targetLevel: targetLevel,
                timeBudgetMinutes: timeBudgetMinutes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> goal = const Value.absent(),
                Value<String> targetLevel = const Value.absent(),
                Value<int> timeBudgetMinutes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TopicsCompanion.insert(
                id: id,
                name: name,
                goal: goal,
                targetLevel: targetLevel,
                timeBudgetMinutes: timeBudgetMinutes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TopicsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                knowledgeNodesRefs = false,
                learningJourneysRefs = false,
                learningSessionsRefs = false,
                learnerModelsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (knowledgeNodesRefs) db.knowledgeNodes,
                    if (learningJourneysRefs) db.learningJourneys,
                    if (learningSessionsRefs) db.learningSessions,
                    if (learnerModelsRefs) db.learnerModels,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (knowledgeNodesRefs)
                        await $_getPrefetchedData<
                          TopicRowData,
                          $TopicsTable,
                          KnowledgeNodeRowData
                        >(
                          currentTable: table,
                          referencedTable: $$TopicsTableReferences
                              ._knowledgeNodesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TopicsTableReferences(
                                db,
                                table,
                                p0,
                              ).knowledgeNodesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.topicId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (learningJourneysRefs)
                        await $_getPrefetchedData<
                          TopicRowData,
                          $TopicsTable,
                          LearningJourneyRowData
                        >(
                          currentTable: table,
                          referencedTable: $$TopicsTableReferences
                              ._learningJourneysRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TopicsTableReferences(
                                db,
                                table,
                                p0,
                              ).learningJourneysRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.topicId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (learningSessionsRefs)
                        await $_getPrefetchedData<
                          TopicRowData,
                          $TopicsTable,
                          LearningSessionRowData
                        >(
                          currentTable: table,
                          referencedTable: $$TopicsTableReferences
                              ._learningSessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TopicsTableReferences(
                                db,
                                table,
                                p0,
                              ).learningSessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.topicId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (learnerModelsRefs)
                        await $_getPrefetchedData<
                          TopicRowData,
                          $TopicsTable,
                          LearnerModelRowData
                        >(
                          currentTable: table,
                          referencedTable: $$TopicsTableReferences
                              ._learnerModelsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TopicsTableReferences(
                                db,
                                table,
                                p0,
                              ).learnerModelsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.topicId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$TopicsTableProcessedTableManager =
    ProcessedTableManager<
      _$MindtreeDb,
      $TopicsTable,
      TopicRowData,
      $$TopicsTableFilterComposer,
      $$TopicsTableOrderingComposer,
      $$TopicsTableAnnotationComposer,
      $$TopicsTableCreateCompanionBuilder,
      $$TopicsTableUpdateCompanionBuilder,
      (TopicRowData, $$TopicsTableReferences),
      TopicRowData,
      PrefetchHooks Function({
        bool knowledgeNodesRefs,
        bool learningJourneysRefs,
        bool learningSessionsRefs,
        bool learnerModelsRefs,
      })
    >;
typedef $$KnowledgeNodesTableCreateCompanionBuilder =
    KnowledgeNodesCompanion Function({
      required String id,
      required String topicId,
      Value<String?> parentId,
      required String label,
      Value<String> oneLiner,
      Value<String> details,
      Value<String?> analogy,
      Value<String?> conceptType,
      Value<double> importance,
      Value<double> difficulty,
      Value<int> estimatedTimeMinutes,
      Value<String> state,
      Value<bool> contentLoaded,
      Value<bool> leaf,
      Value<int> level,
      Value<String> relationsJson,
      Value<String> sequencesJson,
      Value<String> sourcesJson,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$KnowledgeNodesTableUpdateCompanionBuilder =
    KnowledgeNodesCompanion Function({
      Value<String> id,
      Value<String> topicId,
      Value<String?> parentId,
      Value<String> label,
      Value<String> oneLiner,
      Value<String> details,
      Value<String?> analogy,
      Value<String?> conceptType,
      Value<double> importance,
      Value<double> difficulty,
      Value<int> estimatedTimeMinutes,
      Value<String> state,
      Value<bool> contentLoaded,
      Value<bool> leaf,
      Value<int> level,
      Value<String> relationsJson,
      Value<String> sequencesJson,
      Value<String> sourcesJson,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$KnowledgeNodesTableReferences
    extends
        BaseReferences<
          _$MindtreeDb,
          $KnowledgeNodesTable,
          KnowledgeNodeRowData
        > {
  $$KnowledgeNodesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TopicsTable _topicIdTable(_$MindtreeDb db) => db.topics.createAlias(
    $_aliasNameGenerator(db.knowledgeNodes.topicId, db.topics.id),
  );

  $$TopicsTableProcessedTableManager get topicId {
    final $_column = $_itemColumn<String>('topic_id')!;

    final manager = $$TopicsTableTableManager(
      $_db,
      $_db.topics,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_topicIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $KnowledgeNodesTable _parentIdTable(_$MindtreeDb db) =>
      db.knowledgeNodes.createAlias(
        $_aliasNameGenerator(db.knowledgeNodes.parentId, db.knowledgeNodes.id),
      );

  $$KnowledgeNodesTableProcessedTableManager? get parentId {
    final $_column = $_itemColumn<String>('parent_id');
    if ($_column == null) return null;
    final manager = $$KnowledgeNodesTableTableManager(
      $_db,
      $_db.knowledgeNodes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_parentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$KnowledgeNodesTableFilterComposer
    extends Composer<_$MindtreeDb, $KnowledgeNodesTable> {
  $$KnowledgeNodesTableFilterComposer({
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

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get oneLiner => $composableBuilder(
    column: $table.oneLiner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get details => $composableBuilder(
    column: $table.details,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get analogy => $composableBuilder(
    column: $table.analogy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conceptType => $composableBuilder(
    column: $table.conceptType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get importance => $composableBuilder(
    column: $table.importance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estimatedTimeMinutes => $composableBuilder(
    column: $table.estimatedTimeMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get contentLoaded => $composableBuilder(
    column: $table.contentLoaded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get leaf => $composableBuilder(
    column: $table.leaf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relationsJson => $composableBuilder(
    column: $table.relationsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sequencesJson => $composableBuilder(
    column: $table.sequencesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcesJson => $composableBuilder(
    column: $table.sourcesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$TopicsTableFilterComposer get topicId {
    final $$TopicsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.topicId,
      referencedTable: $db.topics,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TopicsTableFilterComposer(
            $db: $db,
            $table: $db.topics,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$KnowledgeNodesTableFilterComposer get parentId {
    final $$KnowledgeNodesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.knowledgeNodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KnowledgeNodesTableFilterComposer(
            $db: $db,
            $table: $db.knowledgeNodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$KnowledgeNodesTableOrderingComposer
    extends Composer<_$MindtreeDb, $KnowledgeNodesTable> {
  $$KnowledgeNodesTableOrderingComposer({
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

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get oneLiner => $composableBuilder(
    column: $table.oneLiner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get details => $composableBuilder(
    column: $table.details,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get analogy => $composableBuilder(
    column: $table.analogy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conceptType => $composableBuilder(
    column: $table.conceptType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get importance => $composableBuilder(
    column: $table.importance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estimatedTimeMinutes => $composableBuilder(
    column: $table.estimatedTimeMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get contentLoaded => $composableBuilder(
    column: $table.contentLoaded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get leaf => $composableBuilder(
    column: $table.leaf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relationsJson => $composableBuilder(
    column: $table.relationsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sequencesJson => $composableBuilder(
    column: $table.sequencesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcesJson => $composableBuilder(
    column: $table.sourcesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$TopicsTableOrderingComposer get topicId {
    final $$TopicsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.topicId,
      referencedTable: $db.topics,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TopicsTableOrderingComposer(
            $db: $db,
            $table: $db.topics,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$KnowledgeNodesTableOrderingComposer get parentId {
    final $$KnowledgeNodesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.knowledgeNodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KnowledgeNodesTableOrderingComposer(
            $db: $db,
            $table: $db.knowledgeNodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$KnowledgeNodesTableAnnotationComposer
    extends Composer<_$MindtreeDb, $KnowledgeNodesTable> {
  $$KnowledgeNodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get oneLiner =>
      $composableBuilder(column: $table.oneLiner, builder: (column) => column);

  GeneratedColumn<String> get details =>
      $composableBuilder(column: $table.details, builder: (column) => column);

  GeneratedColumn<String> get analogy =>
      $composableBuilder(column: $table.analogy, builder: (column) => column);

  GeneratedColumn<String> get conceptType => $composableBuilder(
    column: $table.conceptType,
    builder: (column) => column,
  );

  GeneratedColumn<double> get importance => $composableBuilder(
    column: $table.importance,
    builder: (column) => column,
  );

  GeneratedColumn<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => column,
  );

  GeneratedColumn<int> get estimatedTimeMinutes => $composableBuilder(
    column: $table.estimatedTimeMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<bool> get contentLoaded => $composableBuilder(
    column: $table.contentLoaded,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get leaf =>
      $composableBuilder(column: $table.leaf, builder: (column) => column);

  GeneratedColumn<int> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<String> get relationsJson => $composableBuilder(
    column: $table.relationsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sequencesJson => $composableBuilder(
    column: $table.sequencesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourcesJson => $composableBuilder(
    column: $table.sourcesJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$TopicsTableAnnotationComposer get topicId {
    final $$TopicsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.topicId,
      referencedTable: $db.topics,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TopicsTableAnnotationComposer(
            $db: $db,
            $table: $db.topics,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$KnowledgeNodesTableAnnotationComposer get parentId {
    final $$KnowledgeNodesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.knowledgeNodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KnowledgeNodesTableAnnotationComposer(
            $db: $db,
            $table: $db.knowledgeNodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$KnowledgeNodesTableTableManager
    extends
        RootTableManager<
          _$MindtreeDb,
          $KnowledgeNodesTable,
          KnowledgeNodeRowData,
          $$KnowledgeNodesTableFilterComposer,
          $$KnowledgeNodesTableOrderingComposer,
          $$KnowledgeNodesTableAnnotationComposer,
          $$KnowledgeNodesTableCreateCompanionBuilder,
          $$KnowledgeNodesTableUpdateCompanionBuilder,
          (KnowledgeNodeRowData, $$KnowledgeNodesTableReferences),
          KnowledgeNodeRowData,
          PrefetchHooks Function({bool topicId, bool parentId})
        > {
  $$KnowledgeNodesTableTableManager(_$MindtreeDb db, $KnowledgeNodesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KnowledgeNodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KnowledgeNodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KnowledgeNodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> topicId = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> oneLiner = const Value.absent(),
                Value<String> details = const Value.absent(),
                Value<String?> analogy = const Value.absent(),
                Value<String?> conceptType = const Value.absent(),
                Value<double> importance = const Value.absent(),
                Value<double> difficulty = const Value.absent(),
                Value<int> estimatedTimeMinutes = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<bool> contentLoaded = const Value.absent(),
                Value<bool> leaf = const Value.absent(),
                Value<int> level = const Value.absent(),
                Value<String> relationsJson = const Value.absent(),
                Value<String> sequencesJson = const Value.absent(),
                Value<String> sourcesJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KnowledgeNodesCompanion(
                id: id,
                topicId: topicId,
                parentId: parentId,
                label: label,
                oneLiner: oneLiner,
                details: details,
                analogy: analogy,
                conceptType: conceptType,
                importance: importance,
                difficulty: difficulty,
                estimatedTimeMinutes: estimatedTimeMinutes,
                state: state,
                contentLoaded: contentLoaded,
                leaf: leaf,
                level: level,
                relationsJson: relationsJson,
                sequencesJson: sequencesJson,
                sourcesJson: sourcesJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String topicId,
                Value<String?> parentId = const Value.absent(),
                required String label,
                Value<String> oneLiner = const Value.absent(),
                Value<String> details = const Value.absent(),
                Value<String?> analogy = const Value.absent(),
                Value<String?> conceptType = const Value.absent(),
                Value<double> importance = const Value.absent(),
                Value<double> difficulty = const Value.absent(),
                Value<int> estimatedTimeMinutes = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<bool> contentLoaded = const Value.absent(),
                Value<bool> leaf = const Value.absent(),
                Value<int> level = const Value.absent(),
                Value<String> relationsJson = const Value.absent(),
                Value<String> sequencesJson = const Value.absent(),
                Value<String> sourcesJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KnowledgeNodesCompanion.insert(
                id: id,
                topicId: topicId,
                parentId: parentId,
                label: label,
                oneLiner: oneLiner,
                details: details,
                analogy: analogy,
                conceptType: conceptType,
                importance: importance,
                difficulty: difficulty,
                estimatedTimeMinutes: estimatedTimeMinutes,
                state: state,
                contentLoaded: contentLoaded,
                leaf: leaf,
                level: level,
                relationsJson: relationsJson,
                sequencesJson: sequencesJson,
                sourcesJson: sourcesJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$KnowledgeNodesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({topicId = false, parentId = false}) {
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
                    if (topicId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.topicId,
                                referencedTable: $$KnowledgeNodesTableReferences
                                    ._topicIdTable(db),
                                referencedColumn:
                                    $$KnowledgeNodesTableReferences
                                        ._topicIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (parentId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.parentId,
                                referencedTable: $$KnowledgeNodesTableReferences
                                    ._parentIdTable(db),
                                referencedColumn:
                                    $$KnowledgeNodesTableReferences
                                        ._parentIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$KnowledgeNodesTableProcessedTableManager =
    ProcessedTableManager<
      _$MindtreeDb,
      $KnowledgeNodesTable,
      KnowledgeNodeRowData,
      $$KnowledgeNodesTableFilterComposer,
      $$KnowledgeNodesTableOrderingComposer,
      $$KnowledgeNodesTableAnnotationComposer,
      $$KnowledgeNodesTableCreateCompanionBuilder,
      $$KnowledgeNodesTableUpdateCompanionBuilder,
      (KnowledgeNodeRowData, $$KnowledgeNodesTableReferences),
      KnowledgeNodeRowData,
      PrefetchHooks Function({bool topicId, bool parentId})
    >;
typedef $$LearningJourneysTableCreateCompanionBuilder =
    LearningJourneysCompanion Function({
      required String id,
      required String topicId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$LearningJourneysTableUpdateCompanionBuilder =
    LearningJourneysCompanion Function({
      Value<String> id,
      Value<String> topicId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$LearningJourneysTableReferences
    extends
        BaseReferences<
          _$MindtreeDb,
          $LearningJourneysTable,
          LearningJourneyRowData
        > {
  $$LearningJourneysTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TopicsTable _topicIdTable(_$MindtreeDb db) => db.topics.createAlias(
    $_aliasNameGenerator(db.learningJourneys.topicId, db.topics.id),
  );

  $$TopicsTableProcessedTableManager get topicId {
    final $_column = $_itemColumn<String>('topic_id')!;

    final manager = $$TopicsTableTableManager(
      $_db,
      $_db.topics,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_topicIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $LearningMilestonesTable,
    List<LearningMilestoneRowData>
  >
  _learningMilestonesRefsTable(_$MindtreeDb db) =>
      MultiTypedResultKey.fromTable(
        db.learningMilestones,
        aliasName: $_aliasNameGenerator(
          db.learningJourneys.id,
          db.learningMilestones.journeyId,
        ),
      );

  $$LearningMilestonesTableProcessedTableManager get learningMilestonesRefs {
    final manager = $$LearningMilestonesTableTableManager(
      $_db,
      $_db.learningMilestones,
    ).filter((f) => f.journeyId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _learningMilestonesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $LearningSessionsTable,
    List<LearningSessionRowData>
  >
  _learningSessionsRefsTable(_$MindtreeDb db) => MultiTypedResultKey.fromTable(
    db.learningSessions,
    aliasName: $_aliasNameGenerator(
      db.learningJourneys.id,
      db.learningSessions.journeyId,
    ),
  );

  $$LearningSessionsTableProcessedTableManager get learningSessionsRefs {
    final manager = $$LearningSessionsTableTableManager(
      $_db,
      $_db.learningSessions,
    ).filter((f) => f.journeyId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _learningSessionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LearningJourneysTableFilterComposer
    extends Composer<_$MindtreeDb, $LearningJourneysTable> {
  $$LearningJourneysTableFilterComposer({
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

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$TopicsTableFilterComposer get topicId {
    final $$TopicsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.topicId,
      referencedTable: $db.topics,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TopicsTableFilterComposer(
            $db: $db,
            $table: $db.topics,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> learningMilestonesRefs(
    Expression<bool> Function($$LearningMilestonesTableFilterComposer f) f,
  ) {
    final $$LearningMilestonesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.learningMilestones,
      getReferencedColumn: (t) => t.journeyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningMilestonesTableFilterComposer(
            $db: $db,
            $table: $db.learningMilestones,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> learningSessionsRefs(
    Expression<bool> Function($$LearningSessionsTableFilterComposer f) f,
  ) {
    final $$LearningSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.journeyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableFilterComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LearningJourneysTableOrderingComposer
    extends Composer<_$MindtreeDb, $LearningJourneysTable> {
  $$LearningJourneysTableOrderingComposer({
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

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$TopicsTableOrderingComposer get topicId {
    final $$TopicsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.topicId,
      referencedTable: $db.topics,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TopicsTableOrderingComposer(
            $db: $db,
            $table: $db.topics,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LearningJourneysTableAnnotationComposer
    extends Composer<_$MindtreeDb, $LearningJourneysTable> {
  $$LearningJourneysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$TopicsTableAnnotationComposer get topicId {
    final $$TopicsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.topicId,
      referencedTable: $db.topics,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TopicsTableAnnotationComposer(
            $db: $db,
            $table: $db.topics,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> learningMilestonesRefs<T extends Object>(
    Expression<T> Function($$LearningMilestonesTableAnnotationComposer a) f,
  ) {
    final $$LearningMilestonesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.learningMilestones,
          getReferencedColumn: (t) => t.journeyId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LearningMilestonesTableAnnotationComposer(
                $db: $db,
                $table: $db.learningMilestones,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> learningSessionsRefs<T extends Object>(
    Expression<T> Function($$LearningSessionsTableAnnotationComposer a) f,
  ) {
    final $$LearningSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.journeyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LearningJourneysTableTableManager
    extends
        RootTableManager<
          _$MindtreeDb,
          $LearningJourneysTable,
          LearningJourneyRowData,
          $$LearningJourneysTableFilterComposer,
          $$LearningJourneysTableOrderingComposer,
          $$LearningJourneysTableAnnotationComposer,
          $$LearningJourneysTableCreateCompanionBuilder,
          $$LearningJourneysTableUpdateCompanionBuilder,
          (LearningJourneyRowData, $$LearningJourneysTableReferences),
          LearningJourneyRowData,
          PrefetchHooks Function({
            bool topicId,
            bool learningMilestonesRefs,
            bool learningSessionsRefs,
          })
        > {
  $$LearningJourneysTableTableManager(
    _$MindtreeDb db,
    $LearningJourneysTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LearningJourneysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LearningJourneysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LearningJourneysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> topicId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LearningJourneysCompanion(
                id: id,
                topicId: topicId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String topicId,
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LearningJourneysCompanion.insert(
                id: id,
                topicId: topicId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LearningJourneysTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                topicId = false,
                learningMilestonesRefs = false,
                learningSessionsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (learningMilestonesRefs) db.learningMilestones,
                    if (learningSessionsRefs) db.learningSessions,
                  ],
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
                        if (topicId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.topicId,
                                    referencedTable:
                                        $$LearningJourneysTableReferences
                                            ._topicIdTable(db),
                                    referencedColumn:
                                        $$LearningJourneysTableReferences
                                            ._topicIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (learningMilestonesRefs)
                        await $_getPrefetchedData<
                          LearningJourneyRowData,
                          $LearningJourneysTable,
                          LearningMilestoneRowData
                        >(
                          currentTable: table,
                          referencedTable: $$LearningJourneysTableReferences
                              ._learningMilestonesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LearningJourneysTableReferences(
                                db,
                                table,
                                p0,
                              ).learningMilestonesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.journeyId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (learningSessionsRefs)
                        await $_getPrefetchedData<
                          LearningJourneyRowData,
                          $LearningJourneysTable,
                          LearningSessionRowData
                        >(
                          currentTable: table,
                          referencedTable: $$LearningJourneysTableReferences
                              ._learningSessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LearningJourneysTableReferences(
                                db,
                                table,
                                p0,
                              ).learningSessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.journeyId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$LearningJourneysTableProcessedTableManager =
    ProcessedTableManager<
      _$MindtreeDb,
      $LearningJourneysTable,
      LearningJourneyRowData,
      $$LearningJourneysTableFilterComposer,
      $$LearningJourneysTableOrderingComposer,
      $$LearningJourneysTableAnnotationComposer,
      $$LearningJourneysTableCreateCompanionBuilder,
      $$LearningJourneysTableUpdateCompanionBuilder,
      (LearningJourneyRowData, $$LearningJourneysTableReferences),
      LearningJourneyRowData,
      PrefetchHooks Function({
        bool topicId,
        bool learningMilestonesRefs,
        bool learningSessionsRefs,
      })
    >;
typedef $$LearningMilestonesTableCreateCompanionBuilder =
    LearningMilestonesCompanion Function({
      required String id,
      required String journeyId,
      required String level,
      required String title,
      Value<String> description,
      Value<String> capabilitiesJson,
      Value<double> estimatedHours,
      Value<String> status,
      Value<String> alternativePathsJson,
      Value<int> rowid,
    });
typedef $$LearningMilestonesTableUpdateCompanionBuilder =
    LearningMilestonesCompanion Function({
      Value<String> id,
      Value<String> journeyId,
      Value<String> level,
      Value<String> title,
      Value<String> description,
      Value<String> capabilitiesJson,
      Value<double> estimatedHours,
      Value<String> status,
      Value<String> alternativePathsJson,
      Value<int> rowid,
    });

final class $$LearningMilestonesTableReferences
    extends
        BaseReferences<
          _$MindtreeDb,
          $LearningMilestonesTable,
          LearningMilestoneRowData
        > {
  $$LearningMilestonesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LearningJourneysTable _journeyIdTable(_$MindtreeDb db) =>
      db.learningJourneys.createAlias(
        $_aliasNameGenerator(
          db.learningMilestones.journeyId,
          db.learningJourneys.id,
        ),
      );

  $$LearningJourneysTableProcessedTableManager get journeyId {
    final $_column = $_itemColumn<String>('journey_id')!;

    final manager = $$LearningJourneysTableTableManager(
      $_db,
      $_db.learningJourneys,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_journeyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $LearningSessionsTable,
    List<LearningSessionRowData>
  >
  _learningSessionsRefsTable(_$MindtreeDb db) => MultiTypedResultKey.fromTable(
    db.learningSessions,
    aliasName: $_aliasNameGenerator(
      db.learningMilestones.id,
      db.learningSessions.milestoneId,
    ),
  );

  $$LearningSessionsTableProcessedTableManager get learningSessionsRefs {
    final manager = $$LearningSessionsTableTableManager(
      $_db,
      $_db.learningSessions,
    ).filter((f) => f.milestoneId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _learningSessionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LearningMilestonesTableFilterComposer
    extends Composer<_$MindtreeDb, $LearningMilestonesTable> {
  $$LearningMilestonesTableFilterComposer({
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

  ColumnFilters<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get capabilitiesJson => $composableBuilder(
    column: $table.capabilitiesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get estimatedHours => $composableBuilder(
    column: $table.estimatedHours,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alternativePathsJson => $composableBuilder(
    column: $table.alternativePathsJson,
    builder: (column) => ColumnFilters(column),
  );

  $$LearningJourneysTableFilterComposer get journeyId {
    final $$LearningJourneysTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.journeyId,
      referencedTable: $db.learningJourneys,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningJourneysTableFilterComposer(
            $db: $db,
            $table: $db.learningJourneys,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> learningSessionsRefs(
    Expression<bool> Function($$LearningSessionsTableFilterComposer f) f,
  ) {
    final $$LearningSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.milestoneId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableFilterComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LearningMilestonesTableOrderingComposer
    extends Composer<_$MindtreeDb, $LearningMilestonesTable> {
  $$LearningMilestonesTableOrderingComposer({
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

  ColumnOrderings<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get capabilitiesJson => $composableBuilder(
    column: $table.capabilitiesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get estimatedHours => $composableBuilder(
    column: $table.estimatedHours,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alternativePathsJson => $composableBuilder(
    column: $table.alternativePathsJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$LearningJourneysTableOrderingComposer get journeyId {
    final $$LearningJourneysTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.journeyId,
      referencedTable: $db.learningJourneys,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningJourneysTableOrderingComposer(
            $db: $db,
            $table: $db.learningJourneys,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LearningMilestonesTableAnnotationComposer
    extends Composer<_$MindtreeDb, $LearningMilestonesTable> {
  $$LearningMilestonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get capabilitiesJson => $composableBuilder(
    column: $table.capabilitiesJson,
    builder: (column) => column,
  );

  GeneratedColumn<double> get estimatedHours => $composableBuilder(
    column: $table.estimatedHours,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get alternativePathsJson => $composableBuilder(
    column: $table.alternativePathsJson,
    builder: (column) => column,
  );

  $$LearningJourneysTableAnnotationComposer get journeyId {
    final $$LearningJourneysTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.journeyId,
      referencedTable: $db.learningJourneys,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningJourneysTableAnnotationComposer(
            $db: $db,
            $table: $db.learningJourneys,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> learningSessionsRefs<T extends Object>(
    Expression<T> Function($$LearningSessionsTableAnnotationComposer a) f,
  ) {
    final $$LearningSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.milestoneId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LearningMilestonesTableTableManager
    extends
        RootTableManager<
          _$MindtreeDb,
          $LearningMilestonesTable,
          LearningMilestoneRowData,
          $$LearningMilestonesTableFilterComposer,
          $$LearningMilestonesTableOrderingComposer,
          $$LearningMilestonesTableAnnotationComposer,
          $$LearningMilestonesTableCreateCompanionBuilder,
          $$LearningMilestonesTableUpdateCompanionBuilder,
          (LearningMilestoneRowData, $$LearningMilestonesTableReferences),
          LearningMilestoneRowData,
          PrefetchHooks Function({bool journeyId, bool learningSessionsRefs})
        > {
  $$LearningMilestonesTableTableManager(
    _$MindtreeDb db,
    $LearningMilestonesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LearningMilestonesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LearningMilestonesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LearningMilestonesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> journeyId = const Value.absent(),
                Value<String> level = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> capabilitiesJson = const Value.absent(),
                Value<double> estimatedHours = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> alternativePathsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LearningMilestonesCompanion(
                id: id,
                journeyId: journeyId,
                level: level,
                title: title,
                description: description,
                capabilitiesJson: capabilitiesJson,
                estimatedHours: estimatedHours,
                status: status,
                alternativePathsJson: alternativePathsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String journeyId,
                required String level,
                required String title,
                Value<String> description = const Value.absent(),
                Value<String> capabilitiesJson = const Value.absent(),
                Value<double> estimatedHours = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> alternativePathsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LearningMilestonesCompanion.insert(
                id: id,
                journeyId: journeyId,
                level: level,
                title: title,
                description: description,
                capabilitiesJson: capabilitiesJson,
                estimatedHours: estimatedHours,
                status: status,
                alternativePathsJson: alternativePathsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LearningMilestonesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({journeyId = false, learningSessionsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (learningSessionsRefs) db.learningSessions,
                  ],
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
                        if (journeyId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.journeyId,
                                    referencedTable:
                                        $$LearningMilestonesTableReferences
                                            ._journeyIdTable(db),
                                    referencedColumn:
                                        $$LearningMilestonesTableReferences
                                            ._journeyIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (learningSessionsRefs)
                        await $_getPrefetchedData<
                          LearningMilestoneRowData,
                          $LearningMilestonesTable,
                          LearningSessionRowData
                        >(
                          currentTable: table,
                          referencedTable: $$LearningMilestonesTableReferences
                              ._learningSessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LearningMilestonesTableReferences(
                                db,
                                table,
                                p0,
                              ).learningSessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.milestoneId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$LearningMilestonesTableProcessedTableManager =
    ProcessedTableManager<
      _$MindtreeDb,
      $LearningMilestonesTable,
      LearningMilestoneRowData,
      $$LearningMilestonesTableFilterComposer,
      $$LearningMilestonesTableOrderingComposer,
      $$LearningMilestonesTableAnnotationComposer,
      $$LearningMilestonesTableCreateCompanionBuilder,
      $$LearningMilestonesTableUpdateCompanionBuilder,
      (LearningMilestoneRowData, $$LearningMilestonesTableReferences),
      LearningMilestoneRowData,
      PrefetchHooks Function({bool journeyId, bool learningSessionsRefs})
    >;
typedef $$LearningSessionsTableCreateCompanionBuilder =
    LearningSessionsCompanion Function({
      required String id,
      required String journeyId,
      Value<String?> milestoneId,
      required String topicId,
      Value<String> goal,
      Value<int> timeBudgetMinutes,
      Value<DateTime> startedAt,
      Value<DateTime?> completedAt,
      Value<String> status,
      Value<String> curriculumJson,
      Value<int> currentIndex,
      Value<String> activityJson,
      Value<int> currentActivityStep,
      Value<int> rowid,
    });
typedef $$LearningSessionsTableUpdateCompanionBuilder =
    LearningSessionsCompanion Function({
      Value<String> id,
      Value<String> journeyId,
      Value<String?> milestoneId,
      Value<String> topicId,
      Value<String> goal,
      Value<int> timeBudgetMinutes,
      Value<DateTime> startedAt,
      Value<DateTime?> completedAt,
      Value<String> status,
      Value<String> curriculumJson,
      Value<int> currentIndex,
      Value<String> activityJson,
      Value<int> currentActivityStep,
      Value<int> rowid,
    });

final class $$LearningSessionsTableReferences
    extends
        BaseReferences<
          _$MindtreeDb,
          $LearningSessionsTable,
          LearningSessionRowData
        > {
  $$LearningSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LearningJourneysTable _journeyIdTable(_$MindtreeDb db) =>
      db.learningJourneys.createAlias(
        $_aliasNameGenerator(
          db.learningSessions.journeyId,
          db.learningJourneys.id,
        ),
      );

  $$LearningJourneysTableProcessedTableManager get journeyId {
    final $_column = $_itemColumn<String>('journey_id')!;

    final manager = $$LearningJourneysTableTableManager(
      $_db,
      $_db.learningJourneys,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_journeyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $LearningMilestonesTable _milestoneIdTable(_$MindtreeDb db) =>
      db.learningMilestones.createAlias(
        $_aliasNameGenerator(
          db.learningSessions.milestoneId,
          db.learningMilestones.id,
        ),
      );

  $$LearningMilestonesTableProcessedTableManager? get milestoneId {
    final $_column = $_itemColumn<String>('milestone_id');
    if ($_column == null) return null;
    final manager = $$LearningMilestonesTableTableManager(
      $_db,
      $_db.learningMilestones,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_milestoneIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TopicsTable _topicIdTable(_$MindtreeDb db) => db.topics.createAlias(
    $_aliasNameGenerator(db.learningSessions.topicId, db.topics.id),
  );

  $$TopicsTableProcessedTableManager get topicId {
    final $_column = $_itemColumn<String>('topic_id')!;

    final manager = $$TopicsTableTableManager(
      $_db,
      $_db.topics,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_topicIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$LearningEventsTable, List<LearningEventRowData>>
  _learningEventsRefsTable(_$MindtreeDb db) => MultiTypedResultKey.fromTable(
    db.learningEvents,
    aliasName: $_aliasNameGenerator(
      db.learningSessions.id,
      db.learningEvents.sessionId,
    ),
  );

  $$LearningEventsTableProcessedTableManager get learningEventsRefs {
    final manager = $$LearningEventsTableTableManager(
      $_db,
      $_db.learningEvents,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_learningEventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AssessmentsTable, List<AssessmentRowData>>
  _assessmentsRefsTable(_$MindtreeDb db) => MultiTypedResultKey.fromTable(
    db.assessments,
    aliasName: $_aliasNameGenerator(
      db.learningSessions.id,
      db.assessments.sessionId,
    ),
  );

  $$AssessmentsTableProcessedTableManager get assessmentsRefs {
    final manager = $$AssessmentsTableTableManager(
      $_db,
      $_db.assessments,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_assessmentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LearningSessionsTableFilterComposer
    extends Composer<_$MindtreeDb, $LearningSessionsTable> {
  $$LearningSessionsTableFilterComposer({
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

  ColumnFilters<String> get goal => $composableBuilder(
    column: $table.goal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeBudgetMinutes => $composableBuilder(
    column: $table.timeBudgetMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get curriculumJson => $composableBuilder(
    column: $table.curriculumJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentIndex => $composableBuilder(
    column: $table.currentIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activityJson => $composableBuilder(
    column: $table.activityJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentActivityStep => $composableBuilder(
    column: $table.currentActivityStep,
    builder: (column) => ColumnFilters(column),
  );

  $$LearningJourneysTableFilterComposer get journeyId {
    final $$LearningJourneysTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.journeyId,
      referencedTable: $db.learningJourneys,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningJourneysTableFilterComposer(
            $db: $db,
            $table: $db.learningJourneys,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LearningMilestonesTableFilterComposer get milestoneId {
    final $$LearningMilestonesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.milestoneId,
      referencedTable: $db.learningMilestones,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningMilestonesTableFilterComposer(
            $db: $db,
            $table: $db.learningMilestones,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TopicsTableFilterComposer get topicId {
    final $$TopicsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.topicId,
      referencedTable: $db.topics,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TopicsTableFilterComposer(
            $db: $db,
            $table: $db.topics,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> learningEventsRefs(
    Expression<bool> Function($$LearningEventsTableFilterComposer f) f,
  ) {
    final $$LearningEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.learningEvents,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningEventsTableFilterComposer(
            $db: $db,
            $table: $db.learningEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> assessmentsRefs(
    Expression<bool> Function($$AssessmentsTableFilterComposer f) f,
  ) {
    final $$AssessmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assessments,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssessmentsTableFilterComposer(
            $db: $db,
            $table: $db.assessments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LearningSessionsTableOrderingComposer
    extends Composer<_$MindtreeDb, $LearningSessionsTable> {
  $$LearningSessionsTableOrderingComposer({
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

  ColumnOrderings<String> get goal => $composableBuilder(
    column: $table.goal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeBudgetMinutes => $composableBuilder(
    column: $table.timeBudgetMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get curriculumJson => $composableBuilder(
    column: $table.curriculumJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentIndex => $composableBuilder(
    column: $table.currentIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activityJson => $composableBuilder(
    column: $table.activityJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentActivityStep => $composableBuilder(
    column: $table.currentActivityStep,
    builder: (column) => ColumnOrderings(column),
  );

  $$LearningJourneysTableOrderingComposer get journeyId {
    final $$LearningJourneysTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.journeyId,
      referencedTable: $db.learningJourneys,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningJourneysTableOrderingComposer(
            $db: $db,
            $table: $db.learningJourneys,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LearningMilestonesTableOrderingComposer get milestoneId {
    final $$LearningMilestonesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.milestoneId,
      referencedTable: $db.learningMilestones,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningMilestonesTableOrderingComposer(
            $db: $db,
            $table: $db.learningMilestones,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TopicsTableOrderingComposer get topicId {
    final $$TopicsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.topicId,
      referencedTable: $db.topics,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TopicsTableOrderingComposer(
            $db: $db,
            $table: $db.topics,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LearningSessionsTableAnnotationComposer
    extends Composer<_$MindtreeDb, $LearningSessionsTable> {
  $$LearningSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get goal =>
      $composableBuilder(column: $table.goal, builder: (column) => column);

  GeneratedColumn<int> get timeBudgetMinutes => $composableBuilder(
    column: $table.timeBudgetMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get curriculumJson => $composableBuilder(
    column: $table.curriculumJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get currentIndex => $composableBuilder(
    column: $table.currentIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get activityJson => $composableBuilder(
    column: $table.activityJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get currentActivityStep => $composableBuilder(
    column: $table.currentActivityStep,
    builder: (column) => column,
  );

  $$LearningJourneysTableAnnotationComposer get journeyId {
    final $$LearningJourneysTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.journeyId,
      referencedTable: $db.learningJourneys,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningJourneysTableAnnotationComposer(
            $db: $db,
            $table: $db.learningJourneys,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LearningMilestonesTableAnnotationComposer get milestoneId {
    final $$LearningMilestonesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.milestoneId,
          referencedTable: $db.learningMilestones,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LearningMilestonesTableAnnotationComposer(
                $db: $db,
                $table: $db.learningMilestones,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$TopicsTableAnnotationComposer get topicId {
    final $$TopicsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.topicId,
      referencedTable: $db.topics,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TopicsTableAnnotationComposer(
            $db: $db,
            $table: $db.topics,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> learningEventsRefs<T extends Object>(
    Expression<T> Function($$LearningEventsTableAnnotationComposer a) f,
  ) {
    final $$LearningEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.learningEvents,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.learningEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> assessmentsRefs<T extends Object>(
    Expression<T> Function($$AssessmentsTableAnnotationComposer a) f,
  ) {
    final $$AssessmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assessments,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssessmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.assessments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LearningSessionsTableTableManager
    extends
        RootTableManager<
          _$MindtreeDb,
          $LearningSessionsTable,
          LearningSessionRowData,
          $$LearningSessionsTableFilterComposer,
          $$LearningSessionsTableOrderingComposer,
          $$LearningSessionsTableAnnotationComposer,
          $$LearningSessionsTableCreateCompanionBuilder,
          $$LearningSessionsTableUpdateCompanionBuilder,
          (LearningSessionRowData, $$LearningSessionsTableReferences),
          LearningSessionRowData,
          PrefetchHooks Function({
            bool journeyId,
            bool milestoneId,
            bool topicId,
            bool learningEventsRefs,
            bool assessmentsRefs,
          })
        > {
  $$LearningSessionsTableTableManager(
    _$MindtreeDb db,
    $LearningSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LearningSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LearningSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LearningSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> journeyId = const Value.absent(),
                Value<String?> milestoneId = const Value.absent(),
                Value<String> topicId = const Value.absent(),
                Value<String> goal = const Value.absent(),
                Value<int> timeBudgetMinutes = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> curriculumJson = const Value.absent(),
                Value<int> currentIndex = const Value.absent(),
                Value<String> activityJson = const Value.absent(),
                Value<int> currentActivityStep = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LearningSessionsCompanion(
                id: id,
                journeyId: journeyId,
                milestoneId: milestoneId,
                topicId: topicId,
                goal: goal,
                timeBudgetMinutes: timeBudgetMinutes,
                startedAt: startedAt,
                completedAt: completedAt,
                status: status,
                curriculumJson: curriculumJson,
                currentIndex: currentIndex,
                activityJson: activityJson,
                currentActivityStep: currentActivityStep,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String journeyId,
                Value<String?> milestoneId = const Value.absent(),
                required String topicId,
                Value<String> goal = const Value.absent(),
                Value<int> timeBudgetMinutes = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> curriculumJson = const Value.absent(),
                Value<int> currentIndex = const Value.absent(),
                Value<String> activityJson = const Value.absent(),
                Value<int> currentActivityStep = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LearningSessionsCompanion.insert(
                id: id,
                journeyId: journeyId,
                milestoneId: milestoneId,
                topicId: topicId,
                goal: goal,
                timeBudgetMinutes: timeBudgetMinutes,
                startedAt: startedAt,
                completedAt: completedAt,
                status: status,
                curriculumJson: curriculumJson,
                currentIndex: currentIndex,
                activityJson: activityJson,
                currentActivityStep: currentActivityStep,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LearningSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                journeyId = false,
                milestoneId = false,
                topicId = false,
                learningEventsRefs = false,
                assessmentsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (learningEventsRefs) db.learningEvents,
                    if (assessmentsRefs) db.assessments,
                  ],
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
                        if (journeyId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.journeyId,
                                    referencedTable:
                                        $$LearningSessionsTableReferences
                                            ._journeyIdTable(db),
                                    referencedColumn:
                                        $$LearningSessionsTableReferences
                                            ._journeyIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (milestoneId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.milestoneId,
                                    referencedTable:
                                        $$LearningSessionsTableReferences
                                            ._milestoneIdTable(db),
                                    referencedColumn:
                                        $$LearningSessionsTableReferences
                                            ._milestoneIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (topicId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.topicId,
                                    referencedTable:
                                        $$LearningSessionsTableReferences
                                            ._topicIdTable(db),
                                    referencedColumn:
                                        $$LearningSessionsTableReferences
                                            ._topicIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (learningEventsRefs)
                        await $_getPrefetchedData<
                          LearningSessionRowData,
                          $LearningSessionsTable,
                          LearningEventRowData
                        >(
                          currentTable: table,
                          referencedTable: $$LearningSessionsTableReferences
                              ._learningEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LearningSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).learningEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (assessmentsRefs)
                        await $_getPrefetchedData<
                          LearningSessionRowData,
                          $LearningSessionsTable,
                          AssessmentRowData
                        >(
                          currentTable: table,
                          referencedTable: $$LearningSessionsTableReferences
                              ._assessmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LearningSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).assessmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$LearningSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$MindtreeDb,
      $LearningSessionsTable,
      LearningSessionRowData,
      $$LearningSessionsTableFilterComposer,
      $$LearningSessionsTableOrderingComposer,
      $$LearningSessionsTableAnnotationComposer,
      $$LearningSessionsTableCreateCompanionBuilder,
      $$LearningSessionsTableUpdateCompanionBuilder,
      (LearningSessionRowData, $$LearningSessionsTableReferences),
      LearningSessionRowData,
      PrefetchHooks Function({
        bool journeyId,
        bool milestoneId,
        bool topicId,
        bool learningEventsRefs,
        bool assessmentsRefs,
      })
    >;
typedef $$LearningEventsTableCreateCompanionBuilder =
    LearningEventsCompanion Function({
      required String id,
      required String sessionId,
      Value<DateTime> timestamp,
      required String type,
      Value<String?> nodeId,
      Value<String> dataJson,
      Value<int> durationMs,
      Value<int> rowid,
    });
typedef $$LearningEventsTableUpdateCompanionBuilder =
    LearningEventsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<DateTime> timestamp,
      Value<String> type,
      Value<String?> nodeId,
      Value<String> dataJson,
      Value<int> durationMs,
      Value<int> rowid,
    });

final class $$LearningEventsTableReferences
    extends
        BaseReferences<
          _$MindtreeDb,
          $LearningEventsTable,
          LearningEventRowData
        > {
  $$LearningEventsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LearningSessionsTable _sessionIdTable(_$MindtreeDb db) =>
      db.learningSessions.createAlias(
        $_aliasNameGenerator(
          db.learningEvents.sessionId,
          db.learningSessions.id,
        ),
      );

  $$LearningSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$LearningSessionsTableTableManager(
      $_db,
      $_db.learningSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LearningEventsTableFilterComposer
    extends Composer<_$MindtreeDb, $LearningEventsTable> {
  $$LearningEventsTableFilterComposer({
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

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nodeId => $composableBuilder(
    column: $table.nodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  $$LearningSessionsTableFilterComposer get sessionId {
    final $$LearningSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableFilterComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LearningEventsTableOrderingComposer
    extends Composer<_$MindtreeDb, $LearningEventsTable> {
  $$LearningEventsTableOrderingComposer({
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

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nodeId => $composableBuilder(
    column: $table.nodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$LearningSessionsTableOrderingComposer get sessionId {
    final $$LearningSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LearningEventsTableAnnotationComposer
    extends Composer<_$MindtreeDb, $LearningEventsTable> {
  $$LearningEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get nodeId =>
      $composableBuilder(column: $table.nodeId, builder: (column) => column);

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  $$LearningSessionsTableAnnotationComposer get sessionId {
    final $$LearningSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LearningEventsTableTableManager
    extends
        RootTableManager<
          _$MindtreeDb,
          $LearningEventsTable,
          LearningEventRowData,
          $$LearningEventsTableFilterComposer,
          $$LearningEventsTableOrderingComposer,
          $$LearningEventsTableAnnotationComposer,
          $$LearningEventsTableCreateCompanionBuilder,
          $$LearningEventsTableUpdateCompanionBuilder,
          (LearningEventRowData, $$LearningEventsTableReferences),
          LearningEventRowData,
          PrefetchHooks Function({bool sessionId})
        > {
  $$LearningEventsTableTableManager(_$MindtreeDb db, $LearningEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LearningEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LearningEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LearningEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> nodeId = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LearningEventsCompanion(
                id: id,
                sessionId: sessionId,
                timestamp: timestamp,
                type: type,
                nodeId: nodeId,
                dataJson: dataJson,
                durationMs: durationMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                Value<DateTime> timestamp = const Value.absent(),
                required String type,
                Value<String?> nodeId = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LearningEventsCompanion.insert(
                id: id,
                sessionId: sessionId,
                timestamp: timestamp,
                type: type,
                nodeId: nodeId,
                dataJson: dataJson,
                durationMs: durationMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LearningEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
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
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable: $$LearningEventsTableReferences
                                    ._sessionIdTable(db),
                                referencedColumn:
                                    $$LearningEventsTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$LearningEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$MindtreeDb,
      $LearningEventsTable,
      LearningEventRowData,
      $$LearningEventsTableFilterComposer,
      $$LearningEventsTableOrderingComposer,
      $$LearningEventsTableAnnotationComposer,
      $$LearningEventsTableCreateCompanionBuilder,
      $$LearningEventsTableUpdateCompanionBuilder,
      (LearningEventRowData, $$LearningEventsTableReferences),
      LearningEventRowData,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$LearnerModelsTableCreateCompanionBuilder =
    LearnerModelsCompanion Function({
      required String id,
      Value<String> userId,
      required String topicId,
      Value<String> overallLevel,
      Value<String> conceptMasteriesJson,
      Value<DateTime> updatedAt,
      Value<String> initialOverallLevel,
      Value<int> rowid,
    });
typedef $$LearnerModelsTableUpdateCompanionBuilder =
    LearnerModelsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> topicId,
      Value<String> overallLevel,
      Value<String> conceptMasteriesJson,
      Value<DateTime> updatedAt,
      Value<String> initialOverallLevel,
      Value<int> rowid,
    });

final class $$LearnerModelsTableReferences
    extends
        BaseReferences<_$MindtreeDb, $LearnerModelsTable, LearnerModelRowData> {
  $$LearnerModelsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TopicsTable _topicIdTable(_$MindtreeDb db) => db.topics.createAlias(
    $_aliasNameGenerator(db.learnerModels.topicId, db.topics.id),
  );

  $$TopicsTableProcessedTableManager get topicId {
    final $_column = $_itemColumn<String>('topic_id')!;

    final manager = $$TopicsTableTableManager(
      $_db,
      $_db.topics,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_topicIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LearnerModelsTableFilterComposer
    extends Composer<_$MindtreeDb, $LearnerModelsTable> {
  $$LearnerModelsTableFilterComposer({
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

  ColumnFilters<String> get overallLevel => $composableBuilder(
    column: $table.overallLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conceptMasteriesJson => $composableBuilder(
    column: $table.conceptMasteriesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get initialOverallLevel => $composableBuilder(
    column: $table.initialOverallLevel,
    builder: (column) => ColumnFilters(column),
  );

  $$TopicsTableFilterComposer get topicId {
    final $$TopicsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.topicId,
      referencedTable: $db.topics,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TopicsTableFilterComposer(
            $db: $db,
            $table: $db.topics,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LearnerModelsTableOrderingComposer
    extends Composer<_$MindtreeDb, $LearnerModelsTable> {
  $$LearnerModelsTableOrderingComposer({
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

  ColumnOrderings<String> get overallLevel => $composableBuilder(
    column: $table.overallLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conceptMasteriesJson => $composableBuilder(
    column: $table.conceptMasteriesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get initialOverallLevel => $composableBuilder(
    column: $table.initialOverallLevel,
    builder: (column) => ColumnOrderings(column),
  );

  $$TopicsTableOrderingComposer get topicId {
    final $$TopicsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.topicId,
      referencedTable: $db.topics,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TopicsTableOrderingComposer(
            $db: $db,
            $table: $db.topics,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LearnerModelsTableAnnotationComposer
    extends Composer<_$MindtreeDb, $LearnerModelsTable> {
  $$LearnerModelsTableAnnotationComposer({
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

  GeneratedColumn<String> get overallLevel => $composableBuilder(
    column: $table.overallLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get conceptMasteriesJson => $composableBuilder(
    column: $table.conceptMasteriesJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get initialOverallLevel => $composableBuilder(
    column: $table.initialOverallLevel,
    builder: (column) => column,
  );

  $$TopicsTableAnnotationComposer get topicId {
    final $$TopicsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.topicId,
      referencedTable: $db.topics,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TopicsTableAnnotationComposer(
            $db: $db,
            $table: $db.topics,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LearnerModelsTableTableManager
    extends
        RootTableManager<
          _$MindtreeDb,
          $LearnerModelsTable,
          LearnerModelRowData,
          $$LearnerModelsTableFilterComposer,
          $$LearnerModelsTableOrderingComposer,
          $$LearnerModelsTableAnnotationComposer,
          $$LearnerModelsTableCreateCompanionBuilder,
          $$LearnerModelsTableUpdateCompanionBuilder,
          (LearnerModelRowData, $$LearnerModelsTableReferences),
          LearnerModelRowData,
          PrefetchHooks Function({bool topicId})
        > {
  $$LearnerModelsTableTableManager(_$MindtreeDb db, $LearnerModelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LearnerModelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LearnerModelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LearnerModelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> topicId = const Value.absent(),
                Value<String> overallLevel = const Value.absent(),
                Value<String> conceptMasteriesJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> initialOverallLevel = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LearnerModelsCompanion(
                id: id,
                userId: userId,
                topicId: topicId,
                overallLevel: overallLevel,
                conceptMasteriesJson: conceptMasteriesJson,
                updatedAt: updatedAt,
                initialOverallLevel: initialOverallLevel,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> userId = const Value.absent(),
                required String topicId,
                Value<String> overallLevel = const Value.absent(),
                Value<String> conceptMasteriesJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> initialOverallLevel = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LearnerModelsCompanion.insert(
                id: id,
                userId: userId,
                topicId: topicId,
                overallLevel: overallLevel,
                conceptMasteriesJson: conceptMasteriesJson,
                updatedAt: updatedAt,
                initialOverallLevel: initialOverallLevel,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LearnerModelsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({topicId = false}) {
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
                    if (topicId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.topicId,
                                referencedTable: $$LearnerModelsTableReferences
                                    ._topicIdTable(db),
                                referencedColumn: $$LearnerModelsTableReferences
                                    ._topicIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$LearnerModelsTableProcessedTableManager =
    ProcessedTableManager<
      _$MindtreeDb,
      $LearnerModelsTable,
      LearnerModelRowData,
      $$LearnerModelsTableFilterComposer,
      $$LearnerModelsTableOrderingComposer,
      $$LearnerModelsTableAnnotationComposer,
      $$LearnerModelsTableCreateCompanionBuilder,
      $$LearnerModelsTableUpdateCompanionBuilder,
      (LearnerModelRowData, $$LearnerModelsTableReferences),
      LearnerModelRowData,
      PrefetchHooks Function({bool topicId})
    >;
typedef $$AssessmentsTableCreateCompanionBuilder =
    AssessmentsCompanion Function({
      required String id,
      Value<String?> sessionId,
      Value<String> type,
      Value<String> questionsJson,
      Value<DateTime> startedAt,
      Value<DateTime?> completedAt,
      Value<double?> score,
      Value<int> rowid,
    });
typedef $$AssessmentsTableUpdateCompanionBuilder =
    AssessmentsCompanion Function({
      Value<String> id,
      Value<String?> sessionId,
      Value<String> type,
      Value<String> questionsJson,
      Value<DateTime> startedAt,
      Value<DateTime?> completedAt,
      Value<double?> score,
      Value<int> rowid,
    });

final class $$AssessmentsTableReferences
    extends BaseReferences<_$MindtreeDb, $AssessmentsTable, AssessmentRowData> {
  $$AssessmentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $LearningSessionsTable _sessionIdTable(_$MindtreeDb db) =>
      db.learningSessions.createAlias(
        $_aliasNameGenerator(db.assessments.sessionId, db.learningSessions.id),
      );

  $$LearningSessionsTableProcessedTableManager? get sessionId {
    final $_column = $_itemColumn<String>('session_id');
    if ($_column == null) return null;
    final manager = $$LearningSessionsTableTableManager(
      $_db,
      $_db.learningSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $AssessmentAttemptsTable,
    List<AssessmentAttemptRowData>
  >
  _assessmentAttemptsRefsTable(_$MindtreeDb db) =>
      MultiTypedResultKey.fromTable(
        db.assessmentAttempts,
        aliasName: $_aliasNameGenerator(
          db.assessments.id,
          db.assessmentAttempts.assessmentId,
        ),
      );

  $$AssessmentAttemptsTableProcessedTableManager get assessmentAttemptsRefs {
    final manager = $$AssessmentAttemptsTableTableManager(
      $_db,
      $_db.assessmentAttempts,
    ).filter((f) => f.assessmentId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _assessmentAttemptsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AssessmentsTableFilterComposer
    extends Composer<_$MindtreeDb, $AssessmentsTable> {
  $$AssessmentsTableFilterComposer({
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

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get questionsJson => $composableBuilder(
    column: $table.questionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  $$LearningSessionsTableFilterComposer get sessionId {
    final $$LearningSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableFilterComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> assessmentAttemptsRefs(
    Expression<bool> Function($$AssessmentAttemptsTableFilterComposer f) f,
  ) {
    final $$AssessmentAttemptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assessmentAttempts,
      getReferencedColumn: (t) => t.assessmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssessmentAttemptsTableFilterComposer(
            $db: $db,
            $table: $db.assessmentAttempts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AssessmentsTableOrderingComposer
    extends Composer<_$MindtreeDb, $AssessmentsTable> {
  $$AssessmentsTableOrderingComposer({
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

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get questionsJson => $composableBuilder(
    column: $table.questionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  $$LearningSessionsTableOrderingComposer get sessionId {
    final $$LearningSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssessmentsTableAnnotationComposer
    extends Composer<_$MindtreeDb, $AssessmentsTable> {
  $$AssessmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get questionsJson => $composableBuilder(
    column: $table.questionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<double> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  $$LearningSessionsTableAnnotationComposer get sessionId {
    final $$LearningSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> assessmentAttemptsRefs<T extends Object>(
    Expression<T> Function($$AssessmentAttemptsTableAnnotationComposer a) f,
  ) {
    final $$AssessmentAttemptsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.assessmentAttempts,
          getReferencedColumn: (t) => t.assessmentId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AssessmentAttemptsTableAnnotationComposer(
                $db: $db,
                $table: $db.assessmentAttempts,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$AssessmentsTableTableManager
    extends
        RootTableManager<
          _$MindtreeDb,
          $AssessmentsTable,
          AssessmentRowData,
          $$AssessmentsTableFilterComposer,
          $$AssessmentsTableOrderingComposer,
          $$AssessmentsTableAnnotationComposer,
          $$AssessmentsTableCreateCompanionBuilder,
          $$AssessmentsTableUpdateCompanionBuilder,
          (AssessmentRowData, $$AssessmentsTableReferences),
          AssessmentRowData,
          PrefetchHooks Function({bool sessionId, bool assessmentAttemptsRefs})
        > {
  $$AssessmentsTableTableManager(_$MindtreeDb db, $AssessmentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssessmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssessmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssessmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> questionsJson = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<double?> score = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssessmentsCompanion(
                id: id,
                sessionId: sessionId,
                type: type,
                questionsJson: questionsJson,
                startedAt: startedAt,
                completedAt: completedAt,
                score: score,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> sessionId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> questionsJson = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<double?> score = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssessmentsCompanion.insert(
                id: id,
                sessionId: sessionId,
                type: type,
                questionsJson: questionsJson,
                startedAt: startedAt,
                completedAt: completedAt,
                score: score,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AssessmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({sessionId = false, assessmentAttemptsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (assessmentAttemptsRefs) db.assessmentAttempts,
                  ],
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
                        if (sessionId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.sessionId,
                                    referencedTable:
                                        $$AssessmentsTableReferences
                                            ._sessionIdTable(db),
                                    referencedColumn:
                                        $$AssessmentsTableReferences
                                            ._sessionIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (assessmentAttemptsRefs)
                        await $_getPrefetchedData<
                          AssessmentRowData,
                          $AssessmentsTable,
                          AssessmentAttemptRowData
                        >(
                          currentTable: table,
                          referencedTable: $$AssessmentsTableReferences
                              ._assessmentAttemptsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AssessmentsTableReferences(
                                db,
                                table,
                                p0,
                              ).assessmentAttemptsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.assessmentId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$AssessmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$MindtreeDb,
      $AssessmentsTable,
      AssessmentRowData,
      $$AssessmentsTableFilterComposer,
      $$AssessmentsTableOrderingComposer,
      $$AssessmentsTableAnnotationComposer,
      $$AssessmentsTableCreateCompanionBuilder,
      $$AssessmentsTableUpdateCompanionBuilder,
      (AssessmentRowData, $$AssessmentsTableReferences),
      AssessmentRowData,
      PrefetchHooks Function({bool sessionId, bool assessmentAttemptsRefs})
    >;
typedef $$AssessmentAttemptsTableCreateCompanionBuilder =
    AssessmentAttemptsCompanion Function({
      required String id,
      required String assessmentId,
      required String questionId,
      required String answer,
      Value<bool> correct,
      Value<int> timeSpentMs,
      Value<String?> feedback,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$AssessmentAttemptsTableUpdateCompanionBuilder =
    AssessmentAttemptsCompanion Function({
      Value<String> id,
      Value<String> assessmentId,
      Value<String> questionId,
      Value<String> answer,
      Value<bool> correct,
      Value<int> timeSpentMs,
      Value<String?> feedback,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$AssessmentAttemptsTableReferences
    extends
        BaseReferences<
          _$MindtreeDb,
          $AssessmentAttemptsTable,
          AssessmentAttemptRowData
        > {
  $$AssessmentAttemptsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AssessmentsTable _assessmentIdTable(_$MindtreeDb db) =>
      db.assessments.createAlias(
        $_aliasNameGenerator(
          db.assessmentAttempts.assessmentId,
          db.assessments.id,
        ),
      );

  $$AssessmentsTableProcessedTableManager get assessmentId {
    final $_column = $_itemColumn<String>('assessment_id')!;

    final manager = $$AssessmentsTableTableManager(
      $_db,
      $_db.assessments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assessmentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AssessmentAttemptsTableFilterComposer
    extends Composer<_$MindtreeDb, $AssessmentAttemptsTable> {
  $$AssessmentAttemptsTableFilterComposer({
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

  ColumnFilters<String> get questionId => $composableBuilder(
    column: $table.questionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get answer => $composableBuilder(
    column: $table.answer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get correct => $composableBuilder(
    column: $table.correct,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeSpentMs => $composableBuilder(
    column: $table.timeSpentMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get feedback => $composableBuilder(
    column: $table.feedback,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$AssessmentsTableFilterComposer get assessmentId {
    final $$AssessmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assessmentId,
      referencedTable: $db.assessments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssessmentsTableFilterComposer(
            $db: $db,
            $table: $db.assessments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssessmentAttemptsTableOrderingComposer
    extends Composer<_$MindtreeDb, $AssessmentAttemptsTable> {
  $$AssessmentAttemptsTableOrderingComposer({
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

  ColumnOrderings<String> get questionId => $composableBuilder(
    column: $table.questionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get answer => $composableBuilder(
    column: $table.answer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get correct => $composableBuilder(
    column: $table.correct,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeSpentMs => $composableBuilder(
    column: $table.timeSpentMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get feedback => $composableBuilder(
    column: $table.feedback,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$AssessmentsTableOrderingComposer get assessmentId {
    final $$AssessmentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assessmentId,
      referencedTable: $db.assessments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssessmentsTableOrderingComposer(
            $db: $db,
            $table: $db.assessments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssessmentAttemptsTableAnnotationComposer
    extends Composer<_$MindtreeDb, $AssessmentAttemptsTable> {
  $$AssessmentAttemptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get questionId => $composableBuilder(
    column: $table.questionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get answer =>
      $composableBuilder(column: $table.answer, builder: (column) => column);

  GeneratedColumn<bool> get correct =>
      $composableBuilder(column: $table.correct, builder: (column) => column);

  GeneratedColumn<int> get timeSpentMs => $composableBuilder(
    column: $table.timeSpentMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get feedback =>
      $composableBuilder(column: $table.feedback, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$AssessmentsTableAnnotationComposer get assessmentId {
    final $$AssessmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assessmentId,
      referencedTable: $db.assessments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssessmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.assessments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssessmentAttemptsTableTableManager
    extends
        RootTableManager<
          _$MindtreeDb,
          $AssessmentAttemptsTable,
          AssessmentAttemptRowData,
          $$AssessmentAttemptsTableFilterComposer,
          $$AssessmentAttemptsTableOrderingComposer,
          $$AssessmentAttemptsTableAnnotationComposer,
          $$AssessmentAttemptsTableCreateCompanionBuilder,
          $$AssessmentAttemptsTableUpdateCompanionBuilder,
          (AssessmentAttemptRowData, $$AssessmentAttemptsTableReferences),
          AssessmentAttemptRowData,
          PrefetchHooks Function({bool assessmentId})
        > {
  $$AssessmentAttemptsTableTableManager(
    _$MindtreeDb db,
    $AssessmentAttemptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssessmentAttemptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssessmentAttemptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssessmentAttemptsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> assessmentId = const Value.absent(),
                Value<String> questionId = const Value.absent(),
                Value<String> answer = const Value.absent(),
                Value<bool> correct = const Value.absent(),
                Value<int> timeSpentMs = const Value.absent(),
                Value<String?> feedback = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssessmentAttemptsCompanion(
                id: id,
                assessmentId: assessmentId,
                questionId: questionId,
                answer: answer,
                correct: correct,
                timeSpentMs: timeSpentMs,
                feedback: feedback,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String assessmentId,
                required String questionId,
                required String answer,
                Value<bool> correct = const Value.absent(),
                Value<int> timeSpentMs = const Value.absent(),
                Value<String?> feedback = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssessmentAttemptsCompanion.insert(
                id: id,
                assessmentId: assessmentId,
                questionId: questionId,
                answer: answer,
                correct: correct,
                timeSpentMs: timeSpentMs,
                feedback: feedback,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AssessmentAttemptsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assessmentId = false}) {
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
                    if (assessmentId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.assessmentId,
                                referencedTable:
                                    $$AssessmentAttemptsTableReferences
                                        ._assessmentIdTable(db),
                                referencedColumn:
                                    $$AssessmentAttemptsTableReferences
                                        ._assessmentIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$AssessmentAttemptsTableProcessedTableManager =
    ProcessedTableManager<
      _$MindtreeDb,
      $AssessmentAttemptsTable,
      AssessmentAttemptRowData,
      $$AssessmentAttemptsTableFilterComposer,
      $$AssessmentAttemptsTableOrderingComposer,
      $$AssessmentAttemptsTableAnnotationComposer,
      $$AssessmentAttemptsTableCreateCompanionBuilder,
      $$AssessmentAttemptsTableUpdateCompanionBuilder,
      (AssessmentAttemptRowData, $$AssessmentAttemptsTableReferences),
      AssessmentAttemptRowData,
      PrefetchHooks Function({bool assessmentId})
    >;

class $MindtreeDbManager {
  final _$MindtreeDb _db;
  $MindtreeDbManager(this._db);
  $$TopicsTableTableManager get topics =>
      $$TopicsTableTableManager(_db, _db.topics);
  $$KnowledgeNodesTableTableManager get knowledgeNodes =>
      $$KnowledgeNodesTableTableManager(_db, _db.knowledgeNodes);
  $$LearningJourneysTableTableManager get learningJourneys =>
      $$LearningJourneysTableTableManager(_db, _db.learningJourneys);
  $$LearningMilestonesTableTableManager get learningMilestones =>
      $$LearningMilestonesTableTableManager(_db, _db.learningMilestones);
  $$LearningSessionsTableTableManager get learningSessions =>
      $$LearningSessionsTableTableManager(_db, _db.learningSessions);
  $$LearningEventsTableTableManager get learningEvents =>
      $$LearningEventsTableTableManager(_db, _db.learningEvents);
  $$LearnerModelsTableTableManager get learnerModels =>
      $$LearnerModelsTableTableManager(_db, _db.learnerModels);
  $$AssessmentsTableTableManager get assessments =>
      $$AssessmentsTableTableManager(_db, _db.assessments);
  $$AssessmentAttemptsTableTableManager get assessmentAttempts =>
      $$AssessmentAttemptsTableTableManager(_db, _db.assessmentAttempts);
}
