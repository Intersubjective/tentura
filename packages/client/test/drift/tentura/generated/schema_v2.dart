// dart format width=80
// GENERATED CODE, DO NOT EDIT BY HAND.
// ignore_for_file: type=lint
import 'package:drift/drift.dart';

class Messages extends Table with TableInfo<Messages, MessagesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Messages(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
      'subject_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> objectId = GeneratedColumn<String>(
      'object_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
      'status', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, subjectId, objectId, content, status, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MessagesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessagesData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      subjectId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}subject_id'])!,
      objectId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}object_id'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}status'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  Messages createAlias(String alias) {
    return Messages(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
}

class MessagesData extends DataClass implements Insertable<MessagesData> {
  final String id;
  final String subjectId;
  final String objectId;
  final String content;
  final int status;
  final DateTime createdAt;
  final DateTime updatedAt;
  const MessagesData(
      {required this.id,
      required this.subjectId,
      required this.objectId,
      required this.content,
      required this.status,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['subject_id'] = Variable<String>(subjectId);
    map['object_id'] = Variable<String>(objectId);
    map['content'] = Variable<String>(content);
    map['status'] = Variable<int>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      subjectId: Value(subjectId),
      objectId: Value(objectId),
      content: Value(content),
      status: Value(status),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory MessagesData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessagesData(
      id: serializer.fromJson<String>(json['id']),
      subjectId: serializer.fromJson<String>(json['subjectId']),
      objectId: serializer.fromJson<String>(json['objectId']),
      content: serializer.fromJson<String>(json['content']),
      status: serializer.fromJson<int>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'subjectId': serializer.toJson<String>(subjectId),
      'objectId': serializer.toJson<String>(objectId),
      'content': serializer.toJson<String>(content),
      'status': serializer.toJson<int>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  MessagesData copyWith(
          {String? id,
          String? subjectId,
          String? objectId,
          String? content,
          int? status,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      MessagesData(
        id: id ?? this.id,
        subjectId: subjectId ?? this.subjectId,
        objectId: objectId ?? this.objectId,
        content: content ?? this.content,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  MessagesData copyWithCompanion(MessagesCompanion data) {
    return MessagesData(
      id: data.id.present ? data.id.value : this.id,
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      objectId: data.objectId.present ? data.objectId.value : this.objectId,
      content: data.content.present ? data.content.value : this.content,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessagesData(')
          ..write('id: $id, ')
          ..write('subjectId: $subjectId, ')
          ..write('objectId: $objectId, ')
          ..write('content: $content, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, subjectId, objectId, content, status, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessagesData &&
          other.id == this.id &&
          other.subjectId == this.subjectId &&
          other.objectId == this.objectId &&
          other.content == this.content &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class MessagesCompanion extends UpdateCompanion<MessagesData> {
  final Value<String> id;
  final Value<String> subjectId;
  final Value<String> objectId;
  final Value<String> content;
  final Value<int> status;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.subjectId = const Value.absent(),
    this.objectId = const Value.absent(),
    this.content = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String subjectId,
    required String objectId,
    required String content,
    required int status,
    required DateTime createdAt,
    required DateTime updatedAt,
  })  : id = Value(id),
        subjectId = Value(subjectId),
        objectId = Value(objectId),
        content = Value(content),
        status = Value(status),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<MessagesData> custom({
    Expression<String>? id,
    Expression<String>? subjectId,
    Expression<String>? objectId,
    Expression<String>? content,
    Expression<int>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (subjectId != null) 'subject_id': subjectId,
      if (objectId != null) 'object_id': objectId,
      if (content != null) 'content': content,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  MessagesCompanion copyWith(
      {Value<String>? id,
      Value<String>? subjectId,
      Value<String>? objectId,
      Value<String>? content,
      Value<int>? status,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt}) {
    return MessagesCompanion(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      objectId: objectId ?? this.objectId,
      content: content ?? this.content,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (objectId.present) {
      map['object_id'] = Variable<String>(objectId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
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
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('subjectId: $subjectId, ')
          ..write('objectId: $objectId, ')
          ..write('content: $content, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class Settings extends Table with TableInfo<Settings, SettingsData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Settings(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> valueText = GeneratedColumn<String>(
      'value_text', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  late final GeneratedColumn<int> valueInt = GeneratedColumn<int>(
      'value_int', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  late final GeneratedColumn<bool> valueBool = GeneratedColumn<bool>(
      'value_bool', aliasedName, true,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("value_bool" IN (0, 1))'));
  @override
  List<GeneratedColumn> get $columns => [key, valueText, valueInt, valueBool];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingsData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingsData(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      valueText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value_text']),
      valueInt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}value_int']),
      valueBool: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}value_bool']),
    );
  }

  @override
  Settings createAlias(String alias) {
    return Settings(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
}

class SettingsData extends DataClass implements Insertable<SettingsData> {
  final String key;
  final String? valueText;
  final int? valueInt;
  final bool? valueBool;
  const SettingsData(
      {required this.key, this.valueText, this.valueInt, this.valueBool});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || valueText != null) {
      map['value_text'] = Variable<String>(valueText);
    }
    if (!nullToAbsent || valueInt != null) {
      map['value_int'] = Variable<int>(valueInt);
    }
    if (!nullToAbsent || valueBool != null) {
      map['value_bool'] = Variable<bool>(valueBool);
    }
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      key: Value(key),
      valueText: valueText == null && nullToAbsent
          ? const Value.absent()
          : Value(valueText),
      valueInt: valueInt == null && nullToAbsent
          ? const Value.absent()
          : Value(valueInt),
      valueBool: valueBool == null && nullToAbsent
          ? const Value.absent()
          : Value(valueBool),
    );
  }

  factory SettingsData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingsData(
      key: serializer.fromJson<String>(json['key']),
      valueText: serializer.fromJson<String?>(json['valueText']),
      valueInt: serializer.fromJson<int?>(json['valueInt']),
      valueBool: serializer.fromJson<bool?>(json['valueBool']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'valueText': serializer.toJson<String?>(valueText),
      'valueInt': serializer.toJson<int?>(valueInt),
      'valueBool': serializer.toJson<bool?>(valueBool),
    };
  }

  SettingsData copyWith(
          {String? key,
          Value<String?> valueText = const Value.absent(),
          Value<int?> valueInt = const Value.absent(),
          Value<bool?> valueBool = const Value.absent()}) =>
      SettingsData(
        key: key ?? this.key,
        valueText: valueText.present ? valueText.value : this.valueText,
        valueInt: valueInt.present ? valueInt.value : this.valueInt,
        valueBool: valueBool.present ? valueBool.value : this.valueBool,
      );
  SettingsData copyWithCompanion(SettingsCompanion data) {
    return SettingsData(
      key: data.key.present ? data.key.value : this.key,
      valueText: data.valueText.present ? data.valueText.value : this.valueText,
      valueInt: data.valueInt.present ? data.valueInt.value : this.valueInt,
      valueBool: data.valueBool.present ? data.valueBool.value : this.valueBool,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingsData(')
          ..write('key: $key, ')
          ..write('valueText: $valueText, ')
          ..write('valueInt: $valueInt, ')
          ..write('valueBool: $valueBool')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, valueText, valueInt, valueBool);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsData &&
          other.key == this.key &&
          other.valueText == this.valueText &&
          other.valueInt == this.valueInt &&
          other.valueBool == this.valueBool);
}

class SettingsCompanion extends UpdateCompanion<SettingsData> {
  final Value<String> key;
  final Value<String?> valueText;
  final Value<int?> valueInt;
  final Value<bool?> valueBool;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.valueText = const Value.absent(),
    this.valueInt = const Value.absent(),
    this.valueBool = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    this.valueText = const Value.absent(),
    this.valueInt = const Value.absent(),
    this.valueBool = const Value.absent(),
  }) : key = Value(key);
  static Insertable<SettingsData> custom({
    Expression<String>? key,
    Expression<String>? valueText,
    Expression<int>? valueInt,
    Expression<bool>? valueBool,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (valueText != null) 'value_text': valueText,
      if (valueInt != null) 'value_int': valueInt,
      if (valueBool != null) 'value_bool': valueBool,
    });
  }

  SettingsCompanion copyWith(
      {Value<String>? key,
      Value<String?>? valueText,
      Value<int?>? valueInt,
      Value<bool?>? valueBool}) {
    return SettingsCompanion(
      key: key ?? this.key,
      valueText: valueText ?? this.valueText,
      valueInt: valueInt ?? this.valueInt,
      valueBool: valueBool ?? this.valueBool,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (valueText.present) {
      map['value_text'] = Variable<String>(valueText.value);
    }
    if (valueInt.present) {
      map['value_int'] = Variable<int>(valueInt.value);
    }
    if (valueBool.present) {
      map['value_bool'] = Variable<bool>(valueBool.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('valueText: $valueText, ')
          ..write('valueInt: $valueInt, ')
          ..write('valueBool: $valueBool')
          ..write(')'))
        .toString();
  }
}

class Friends extends Table with TableInfo<Friends, FriendsData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Friends(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
      'subject_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> objectId = GeneratedColumn<String>(
      'object_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('\'\''));
  late final GeneratedColumn<String> imageId = GeneratedColumn<String>(
      'image_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('\'\''));
  late final GeneratedColumn<String> blurHash = GeneratedColumn<String>(
      'blur_hash', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('\'\''));
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
      'height', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('0'));
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
      'width', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('0'));
  late final GeneratedColumn<bool> hasAvatar = GeneratedColumn<bool>(
      'has_avatar', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("has_avatar" IN (0, 1))'),
      defaultValue: const CustomExpression('0'));
  @override
  List<GeneratedColumn> get $columns =>
      [subjectId, objectId, title, imageId, blurHash, height, width, hasAvatar];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'friends';
  @override
  Set<GeneratedColumn> get $primaryKey => {subjectId, objectId};
  @override
  FriendsData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FriendsData(
      subjectId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}subject_id'])!,
      objectId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}object_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      imageId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}image_id'])!,
      blurHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}blur_hash'])!,
      height: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}height'])!,
      width: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}width'])!,
      hasAvatar: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}has_avatar'])!,
    );
  }

  @override
  Friends createAlias(String alias) {
    return Friends(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
}

class FriendsData extends DataClass implements Insertable<FriendsData> {
  final String subjectId;
  final String objectId;
  final String title;
  final String imageId;
  final String blurHash;
  final int height;
  final int width;
  final bool hasAvatar;
  const FriendsData(
      {required this.subjectId,
      required this.objectId,
      required this.title,
      required this.imageId,
      required this.blurHash,
      required this.height,
      required this.width,
      required this.hasAvatar});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['subject_id'] = Variable<String>(subjectId);
    map['object_id'] = Variable<String>(objectId);
    map['title'] = Variable<String>(title);
    map['image_id'] = Variable<String>(imageId);
    map['blur_hash'] = Variable<String>(blurHash);
    map['height'] = Variable<int>(height);
    map['width'] = Variable<int>(width);
    map['has_avatar'] = Variable<bool>(hasAvatar);
    return map;
  }

  FriendsCompanion toCompanion(bool nullToAbsent) {
    return FriendsCompanion(
      subjectId: Value(subjectId),
      objectId: Value(objectId),
      title: Value(title),
      imageId: Value(imageId),
      blurHash: Value(blurHash),
      height: Value(height),
      width: Value(width),
      hasAvatar: Value(hasAvatar),
    );
  }

  factory FriendsData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FriendsData(
      subjectId: serializer.fromJson<String>(json['subjectId']),
      objectId: serializer.fromJson<String>(json['objectId']),
      title: serializer.fromJson<String>(json['title']),
      imageId: serializer.fromJson<String>(json['imageId']),
      blurHash: serializer.fromJson<String>(json['blurHash']),
      height: serializer.fromJson<int>(json['height']),
      width: serializer.fromJson<int>(json['width']),
      hasAvatar: serializer.fromJson<bool>(json['hasAvatar']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'subjectId': serializer.toJson<String>(subjectId),
      'objectId': serializer.toJson<String>(objectId),
      'title': serializer.toJson<String>(title),
      'imageId': serializer.toJson<String>(imageId),
      'blurHash': serializer.toJson<String>(blurHash),
      'height': serializer.toJson<int>(height),
      'width': serializer.toJson<int>(width),
      'hasAvatar': serializer.toJson<bool>(hasAvatar),
    };
  }

  FriendsData copyWith(
          {String? subjectId,
          String? objectId,
          String? title,
          String? imageId,
          String? blurHash,
          int? height,
          int? width,
          bool? hasAvatar}) =>
      FriendsData(
        subjectId: subjectId ?? this.subjectId,
        objectId: objectId ?? this.objectId,
        title: title ?? this.title,
        imageId: imageId ?? this.imageId,
        blurHash: blurHash ?? this.blurHash,
        height: height ?? this.height,
        width: width ?? this.width,
        hasAvatar: hasAvatar ?? this.hasAvatar,
      );
  FriendsData copyWithCompanion(FriendsCompanion data) {
    return FriendsData(
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      objectId: data.objectId.present ? data.objectId.value : this.objectId,
      title: data.title.present ? data.title.value : this.title,
      imageId: data.imageId.present ? data.imageId.value : this.imageId,
      blurHash: data.blurHash.present ? data.blurHash.value : this.blurHash,
      height: data.height.present ? data.height.value : this.height,
      width: data.width.present ? data.width.value : this.width,
      hasAvatar: data.hasAvatar.present ? data.hasAvatar.value : this.hasAvatar,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FriendsData(')
          ..write('subjectId: $subjectId, ')
          ..write('objectId: $objectId, ')
          ..write('title: $title, ')
          ..write('imageId: $imageId, ')
          ..write('blurHash: $blurHash, ')
          ..write('height: $height, ')
          ..write('width: $width, ')
          ..write('hasAvatar: $hasAvatar')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      subjectId, objectId, title, imageId, blurHash, height, width, hasAvatar);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FriendsData &&
          other.subjectId == this.subjectId &&
          other.objectId == this.objectId &&
          other.title == this.title &&
          other.imageId == this.imageId &&
          other.blurHash == this.blurHash &&
          other.height == this.height &&
          other.width == this.width &&
          other.hasAvatar == this.hasAvatar);
}

class FriendsCompanion extends UpdateCompanion<FriendsData> {
  final Value<String> subjectId;
  final Value<String> objectId;
  final Value<String> title;
  final Value<String> imageId;
  final Value<String> blurHash;
  final Value<int> height;
  final Value<int> width;
  final Value<bool> hasAvatar;
  const FriendsCompanion({
    this.subjectId = const Value.absent(),
    this.objectId = const Value.absent(),
    this.title = const Value.absent(),
    this.imageId = const Value.absent(),
    this.blurHash = const Value.absent(),
    this.height = const Value.absent(),
    this.width = const Value.absent(),
    this.hasAvatar = const Value.absent(),
  });
  FriendsCompanion.insert({
    required String subjectId,
    required String objectId,
    this.title = const Value.absent(),
    this.imageId = const Value.absent(),
    this.blurHash = const Value.absent(),
    this.height = const Value.absent(),
    this.width = const Value.absent(),
    this.hasAvatar = const Value.absent(),
  })  : subjectId = Value(subjectId),
        objectId = Value(objectId);
  static Insertable<FriendsData> custom({
    Expression<String>? subjectId,
    Expression<String>? objectId,
    Expression<String>? title,
    Expression<String>? imageId,
    Expression<String>? blurHash,
    Expression<int>? height,
    Expression<int>? width,
    Expression<bool>? hasAvatar,
  }) {
    return RawValuesInsertable({
      if (subjectId != null) 'subject_id': subjectId,
      if (objectId != null) 'object_id': objectId,
      if (title != null) 'title': title,
      if (imageId != null) 'image_id': imageId,
      if (blurHash != null) 'blur_hash': blurHash,
      if (height != null) 'height': height,
      if (width != null) 'width': width,
      if (hasAvatar != null) 'has_avatar': hasAvatar,
    });
  }

  FriendsCompanion copyWith(
      {Value<String>? subjectId,
      Value<String>? objectId,
      Value<String>? title,
      Value<String>? imageId,
      Value<String>? blurHash,
      Value<int>? height,
      Value<int>? width,
      Value<bool>? hasAvatar}) {
    return FriendsCompanion(
      subjectId: subjectId ?? this.subjectId,
      objectId: objectId ?? this.objectId,
      title: title ?? this.title,
      imageId: imageId ?? this.imageId,
      blurHash: blurHash ?? this.blurHash,
      height: height ?? this.height,
      width: width ?? this.width,
      hasAvatar: hasAvatar ?? this.hasAvatar,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (objectId.present) {
      map['object_id'] = Variable<String>(objectId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (imageId.present) {
      map['image_id'] = Variable<String>(imageId.value);
    }
    if (blurHash.present) {
      map['blur_hash'] = Variable<String>(blurHash.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (hasAvatar.present) {
      map['has_avatar'] = Variable<bool>(hasAvatar.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FriendsCompanion(')
          ..write('subjectId: $subjectId, ')
          ..write('objectId: $objectId, ')
          ..write('title: $title, ')
          ..write('imageId: $imageId, ')
          ..write('blurHash: $blurHash, ')
          ..write('height: $height, ')
          ..write('width: $width, ')
          ..write('hasAvatar: $hasAvatar')
          ..write(')'))
        .toString();
  }
}

class Accounts extends Table with TableInfo<Accounts, AccountsData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Accounts(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('\'\''));
  late final GeneratedColumn<String> imageId = GeneratedColumn<String>(
      'image_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('\'\''));
  late final GeneratedColumn<String> blurHash = GeneratedColumn<String>(
      'blur_hash', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('\'\''));
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
      'height', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('0'));
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
      'width', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('0'));
  late final GeneratedColumn<bool> hasAvatar = GeneratedColumn<bool>(
      'has_avatar', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("has_avatar" IN (0, 1))'),
      defaultValue: const CustomExpression('0'));
  @override
  List<GeneratedColumn> get $columns =>
      [id, title, imageId, blurHash, height, width, hasAvatar];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AccountsData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountsData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      imageId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}image_id'])!,
      blurHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}blur_hash'])!,
      height: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}height'])!,
      width: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}width'])!,
      hasAvatar: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}has_avatar'])!,
    );
  }

  @override
  Accounts createAlias(String alias) {
    return Accounts(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
}

class AccountsData extends DataClass implements Insertable<AccountsData> {
  final String id;
  final String title;
  final String imageId;
  final String blurHash;
  final int height;
  final int width;
  final bool hasAvatar;
  const AccountsData(
      {required this.id,
      required this.title,
      required this.imageId,
      required this.blurHash,
      required this.height,
      required this.width,
      required this.hasAvatar});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['image_id'] = Variable<String>(imageId);
    map['blur_hash'] = Variable<String>(blurHash);
    map['height'] = Variable<int>(height);
    map['width'] = Variable<int>(width);
    map['has_avatar'] = Variable<bool>(hasAvatar);
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      id: Value(id),
      title: Value(title),
      imageId: Value(imageId),
      blurHash: Value(blurHash),
      height: Value(height),
      width: Value(width),
      hasAvatar: Value(hasAvatar),
    );
  }

  factory AccountsData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountsData(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      imageId: serializer.fromJson<String>(json['imageId']),
      blurHash: serializer.fromJson<String>(json['blurHash']),
      height: serializer.fromJson<int>(json['height']),
      width: serializer.fromJson<int>(json['width']),
      hasAvatar: serializer.fromJson<bool>(json['hasAvatar']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'imageId': serializer.toJson<String>(imageId),
      'blurHash': serializer.toJson<String>(blurHash),
      'height': serializer.toJson<int>(height),
      'width': serializer.toJson<int>(width),
      'hasAvatar': serializer.toJson<bool>(hasAvatar),
    };
  }

  AccountsData copyWith(
          {String? id,
          String? title,
          String? imageId,
          String? blurHash,
          int? height,
          int? width,
          bool? hasAvatar}) =>
      AccountsData(
        id: id ?? this.id,
        title: title ?? this.title,
        imageId: imageId ?? this.imageId,
        blurHash: blurHash ?? this.blurHash,
        height: height ?? this.height,
        width: width ?? this.width,
        hasAvatar: hasAvatar ?? this.hasAvatar,
      );
  AccountsData copyWithCompanion(AccountsCompanion data) {
    return AccountsData(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      imageId: data.imageId.present ? data.imageId.value : this.imageId,
      blurHash: data.blurHash.present ? data.blurHash.value : this.blurHash,
      height: data.height.present ? data.height.value : this.height,
      width: data.width.present ? data.width.value : this.width,
      hasAvatar: data.hasAvatar.present ? data.hasAvatar.value : this.hasAvatar,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountsData(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('imageId: $imageId, ')
          ..write('blurHash: $blurHash, ')
          ..write('height: $height, ')
          ..write('width: $width, ')
          ..write('hasAvatar: $hasAvatar')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, title, imageId, blurHash, height, width, hasAvatar);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountsData &&
          other.id == this.id &&
          other.title == this.title &&
          other.imageId == this.imageId &&
          other.blurHash == this.blurHash &&
          other.height == this.height &&
          other.width == this.width &&
          other.hasAvatar == this.hasAvatar);
}

class AccountsCompanion extends UpdateCompanion<AccountsData> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> imageId;
  final Value<String> blurHash;
  final Value<int> height;
  final Value<int> width;
  final Value<bool> hasAvatar;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.imageId = const Value.absent(),
    this.blurHash = const Value.absent(),
    this.height = const Value.absent(),
    this.width = const Value.absent(),
    this.hasAvatar = const Value.absent(),
  });
  AccountsCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.imageId = const Value.absent(),
    this.blurHash = const Value.absent(),
    this.height = const Value.absent(),
    this.width = const Value.absent(),
    this.hasAvatar = const Value.absent(),
  }) : id = Value(id);
  static Insertable<AccountsData> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? imageId,
    Expression<String>? blurHash,
    Expression<int>? height,
    Expression<int>? width,
    Expression<bool>? hasAvatar,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (imageId != null) 'image_id': imageId,
      if (blurHash != null) 'blur_hash': blurHash,
      if (height != null) 'height': height,
      if (width != null) 'width': width,
      if (hasAvatar != null) 'has_avatar': hasAvatar,
    });
  }

  AccountsCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String>? imageId,
      Value<String>? blurHash,
      Value<int>? height,
      Value<int>? width,
      Value<bool>? hasAvatar}) {
    return AccountsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      imageId: imageId ?? this.imageId,
      blurHash: blurHash ?? this.blurHash,
      height: height ?? this.height,
      width: width ?? this.width,
      hasAvatar: hasAvatar ?? this.hasAvatar,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (imageId.present) {
      map['image_id'] = Variable<String>(imageId.value);
    }
    if (blurHash.present) {
      map['blur_hash'] = Variable<String>(blurHash.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (hasAvatar.present) {
      map['has_avatar'] = Variable<bool>(hasAvatar.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('imageId: $imageId, ')
          ..write('blurHash: $blurHash, ')
          ..write('height: $height, ')
          ..write('width: $width, ')
          ..write('hasAvatar: $hasAvatar')
          ..write(')'))
        .toString();
  }
}

class DatabaseAtV2 extends GeneratedDatabase {
  DatabaseAtV2(QueryExecutor e) : super(e);
  late final Messages messages = Messages(this);
  late final Settings settings = Settings(this);
  late final Index messagesObject = Index('messages_object',
      'CREATE INDEX messages_object ON messages (object_id)');
  late final Index messagesSubject = Index('messages_subject',
      'CREATE INDEX messages_subject ON messages (subject_id)');
  late final Index messagesUpdatedAt = Index('messages_updatedAt',
      'CREATE INDEX messages_updatedAt ON messages (updated_at)');
  late final Friends friends = Friends(this);
  late final Accounts accounts = Accounts(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        messages,
        settings,
        messagesObject,
        messagesSubject,
        messagesUpdatedAt,
        friends,
        accounts
      ];
  @override
  int get schemaVersion => 2;
}
