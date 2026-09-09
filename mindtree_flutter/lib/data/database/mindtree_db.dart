import 'package:drift/drift.dart';

part 'mindtree_db.g.dart';

/// Topics created by the user.
@DataClassName('TopicRowData')
class Topics extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get goal => text().withDefault(const Constant('overview'))();
  TextColumn get targetLevel => text().withDefault(const Constant('basic_understanding'))();
  IntColumn get timeBudgetMinutes => integer().withDefault(const Constant(60))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Knowledge tree nodes.
@DataClassName('KnowledgeNodeRowData')
class KnowledgeNodes extends Table {
  TextColumn get id => text()();
  TextColumn get topicId => text().references(Topics, #id, onDelete: KeyAction.cascade)();
  TextColumn get parentId => text().nullable().references(KnowledgeNodes, #id, onDelete: KeyAction.cascade)();
  TextColumn get label => text()();
  TextColumn get oneLiner => text().withDefault(const Constant(''))();
  TextColumn get details => text().withDefault(const Constant(''))();
  TextColumn get analogy => text().nullable()();
  TextColumn get conceptType => text().nullable()();
  RealColumn get importance => real().withDefault(const Constant(0.5))();
  RealColumn get difficulty => real().withDefault(const Constant(0.5))();
  IntColumn get estimatedTimeMinutes => integer().withDefault(const Constant(5))();
  TextColumn get state => text().withDefault(const Constant('new'))();
  BoolColumn get contentLoaded => boolean().withDefault(const Constant(false))();
  BoolColumn get leaf => boolean().withDefault(const Constant(false))();
  IntColumn get level => integer().withDefault(const Constant(1))();
  TextColumn get relationsJson => text().withDefault(const Constant('[]'))();
  TextColumn get sequencesJson => text().withDefault(const Constant('[]'))();
  TextColumn get sourcesJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [];
}

/// Learning journeys (containers of milestones).
@DataClassName('LearningJourneyRowData')
class LearningJourneys extends Table {
  TextColumn get id => text()();
  TextColumn get topicId => text().references(Topics, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Learning milestones within a journey.
@DataClassName('LearningMilestoneRowData')
class LearningMilestones extends Table {
  TextColumn get id => text()();
  TextColumn get journeyId => text().references(LearningJourneys, #id, onDelete: KeyAction.cascade)();
  TextColumn get level => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get capabilitiesJson => text().withDefault(const Constant('[]'))();
  RealColumn get estimatedHours => real().withDefault(const Constant(1))();
  TextColumn get status => text().withDefault(const Constant('not_started'))();
  TextColumn get alternativePathsJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Learning sessions.
@DataClassName('LearningSessionRowData')
class LearningSessions extends Table {
  TextColumn get id => text()();
  TextColumn get journeyId => text().references(LearningJourneys, #id, onDelete: KeyAction.cascade)();
  TextColumn get milestoneId => text().nullable().references(LearningMilestones, #id)();
  TextColumn get topicId => text().references(Topics, #id, onDelete: KeyAction.cascade)();
  TextColumn get goal => text().withDefault(const Constant('overview'))();
  IntColumn get timeBudgetMinutes => integer().withDefault(const Constant(60))();
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get curriculumJson => text().withDefault(const Constant('{}'))();
  IntColumn get currentIndex => integer().withDefault(const Constant(0))();
  TextColumn get activityJson => text().withDefault(const Constant('[]'))();
  IntColumn get currentActivityStep => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Learning event log.
@DataClassName('LearningEventRowData')
class LearningEvents extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(LearningSessions, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
  TextColumn get type => text()();
  TextColumn get nodeId => text().nullable()();
  TextColumn get dataJson => text().withDefault(const Constant('{}'))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Learner mastery models.
@DataClassName('LearnerModelRowData')
class LearnerModels extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().withDefault(const Constant('default'))();
  TextColumn get topicId => text().references(Topics, #id, onDelete: KeyAction.cascade)();
  TextColumn get overallLevel => text().withDefault(const Constant('awareness'))();
  TextColumn get conceptMasteriesJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get initialOverallLevel => text().withDefault(const Constant('awareness'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {userId, topicId},
      ];
}

/// Assessments (quizzes, diagnostics, finals).
@DataClassName('AssessmentRowData')
class Assessments extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().nullable().references(LearningSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text().withDefault(const Constant('quiz'))();
  TextColumn get questionsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();
  RealColumn get score => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Individual assessment attempts.
@DataClassName('AssessmentAttemptRowData')
class AssessmentAttempts extends Table {
  TextColumn get id => text()();
  TextColumn get assessmentId => text().references(Assessments, #id, onDelete: KeyAction.cascade)();
  TextColumn get questionId => text()();
  TextColumn get answer => text()();
  BoolColumn get correct => boolean().withDefault(const Constant(false))();
  IntColumn get timeSpentMs => integer().withDefault(const Constant(0))();
  TextColumn get feedback => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  Topics,
  KnowledgeNodes,
  LearningJourneys,
  LearningMilestones,
  LearningSessions,
  LearningEvents,
  LearnerModels,
  Assessments,
  AssessmentAttempts,
])
class MindtreeDb extends _$MindtreeDb {
  MindtreeDb(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {},
      );
}
