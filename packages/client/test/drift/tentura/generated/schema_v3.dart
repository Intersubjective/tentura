// dart format width=80
// GENERATED CODE, DO NOT EDIT BY HAND.
// ignore_for_file: type=lint
import 'package:drift/drift.dart';

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
  late final GeneratedColumn<DateTime> fcmTokenUpdatedAt =
      GeneratedColumn<DateTime>('fcm_token_updated_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, title, imageId, blurHash, height, width, fcmTokenUpdatedAt];
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
      fcmTokenUpdatedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}fcm_token_updated_at']),
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
  final DateTime? fcmTokenUpdatedAt;
  const AccountsData(
      {required this.id,
      required this.title,
      required this.imageId,
      required this.blurHash,
      required this.height,
      required this.width,
      this.fcmTokenUpdatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['image_id'] = Variable<String>(imageId);
    map['blur_hash'] = Variable<String>(blurHash);
    map['height'] = Variable<int>(height);
    map['width'] = Variable<int>(width);
    if (!nullToAbsent || fcmTokenUpdatedAt != null) {
      map['fcm_token_updated_at'] = Variable<DateTime>(fcmTokenUpdatedAt);
    }
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
      fcmTokenUpdatedAt: fcmTokenUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(fcmTokenUpdatedAt),
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
      fcmTokenUpdatedAt:
          serializer.fromJson<DateTime?>(json['fcmTokenUpdatedAt']),
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
      'fcmTokenUpdatedAt': serializer.toJson<DateTime?>(fcmTokenUpdatedAt),
    };
  }

  AccountsData copyWith(
          {String? id,
          String? title,
          String? imageId,
          String? blurHash,
          int? height,
          int? width,
          Value<DateTime?> fcmTokenUpdatedAt = const Value.absent()}) =>
      AccountsData(
        id: id ?? this.id,
        title: title ?? this.title,
        imageId: imageId ?? this.imageId,
        blurHash: blurHash ?? this.blurHash,
        height: height ?? this.height,
        width: width ?? this.width,
        fcmTokenUpdatedAt: fcmTokenUpdatedAt.present
            ? fcmTokenUpdatedAt.value
            : this.fcmTokenUpdatedAt,
      );
  AccountsData copyWithCompanion(AccountsCompanion data) {
    return AccountsData(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      imageId: data.imageId.present ? data.imageId.value : this.imageId,
      blurHash: data.blurHash.present ? data.blurHash.value : this.blurHash,
      height: data.height.present ? data.height.value : this.height,
      width: data.width.present ? data.width.value : this.width,
      fcmTokenUpdatedAt: data.fcmTokenUpdatedAt.present
          ? data.fcmTokenUpdatedAt.value
          : this.fcmTokenUpdatedAt,
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
          ..write('fcmTokenUpdatedAt: $fcmTokenUpdatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, title, imageId, blurHash, height, width, fcmTokenUpdatedAt);
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
          other.fcmTokenUpdatedAt == this.fcmTokenUpdatedAt);
}

class AccountsCompanion extends UpdateCompanion<AccountsData> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> imageId;
  final Value<String> blurHash;
  final Value<int> height;
  final Value<int> width;
  final Value<DateTime?> fcmTokenUpdatedAt;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.imageId = const Value.absent(),
    this.blurHash = const Value.absent(),
    this.height = const Value.absent(),
    this.width = const Value.absent(),
    this.fcmTokenUpdatedAt = const Value.absent(),
  });
  AccountsCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.imageId = const Value.absent(),
    this.blurHash = const Value.absent(),
    this.height = const Value.absent(),
    this.width = const Value.absent(),
    this.fcmTokenUpdatedAt = const Value.absent(),
  }) : id = Value(id);
  static Insertable<AccountsData> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? imageId,
    Expression<String>? blurHash,
    Expression<int>? height,
    Expression<int>? width,
    Expression<DateTime>? fcmTokenUpdatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (imageId != null) 'image_id': imageId,
      if (blurHash != null) 'blur_hash': blurHash,
      if (height != null) 'height': height,
      if (width != null) 'width': width,
      if (fcmTokenUpdatedAt != null) 'fcm_token_updated_at': fcmTokenUpdatedAt,
    });
  }

  AccountsCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String>? imageId,
      Value<String>? blurHash,
      Value<int>? height,
      Value<int>? width,
      Value<DateTime?>? fcmTokenUpdatedAt}) {
    return AccountsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      imageId: imageId ?? this.imageId,
      blurHash: blurHash ?? this.blurHash,
      height: height ?? this.height,
      width: width ?? this.width,
      fcmTokenUpdatedAt: fcmTokenUpdatedAt ?? this.fcmTokenUpdatedAt,
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
    if (fcmTokenUpdatedAt.present) {
      map['fcm_token_updated_at'] = Variable<DateTime>(fcmTokenUpdatedAt.value);
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
          ..write('fcmTokenUpdatedAt: $fcmTokenUpdatedAt')
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
  @override
  List<GeneratedColumn> get $columns =>
      [subjectId, objectId, title, imageId, blurHash, height, width];
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
  const FriendsData(
      {required this.subjectId,
      required this.objectId,
      required this.title,
      required this.imageId,
      required this.blurHash,
      required this.height,
      required this.width});
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
    };
  }

  FriendsData copyWith(
          {String? subjectId,
          String? objectId,
          String? title,
          String? imageId,
          String? blurHash,
          int? height,
          int? width}) =>
      FriendsData(
        subjectId: subjectId ?? this.subjectId,
        objectId: objectId ?? this.objectId,
        title: title ?? this.title,
        imageId: imageId ?? this.imageId,
        blurHash: blurHash ?? this.blurHash,
        height: height ?? this.height,
        width: width ?? this.width,
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
          ..write('width: $width')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(subjectId, objectId, title, imageId, blurHash, height, width);
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
          other.width == this.width);
}

class FriendsCompanion extends UpdateCompanion<FriendsData> {
  final Value<String> subjectId;
  final Value<String> objectId;
  final Value<String> title;
  final Value<String> imageId;
  final Value<String> blurHash;
  final Value<int> height;
  final Value<int> width;
  const FriendsCompanion({
    this.subjectId = const Value.absent(),
    this.objectId = const Value.absent(),
    this.title = const Value.absent(),
    this.imageId = const Value.absent(),
    this.blurHash = const Value.absent(),
    this.height = const Value.absent(),
    this.width = const Value.absent(),
  });
  FriendsCompanion.insert({
    required String subjectId,
    required String objectId,
    this.title = const Value.absent(),
    this.imageId = const Value.absent(),
    this.blurHash = const Value.absent(),
    this.height = const Value.absent(),
    this.width = const Value.absent(),
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
  }) {
    return RawValuesInsertable({
      if (subjectId != null) 'subject_id': subjectId,
      if (objectId != null) 'object_id': objectId,
      if (title != null) 'title': title,
      if (imageId != null) 'image_id': imageId,
      if (blurHash != null) 'blur_hash': blurHash,
      if (height != null) 'height': height,
      if (width != null) 'width': width,
    });
  }

  FriendsCompanion copyWith(
      {Value<String>? subjectId,
      Value<String>? objectId,
      Value<String>? title,
      Value<String>? imageId,
      Value<String>? blurHash,
      Value<int>? height,
      Value<int>? width}) {
    return FriendsCompanion(
      subjectId: subjectId ?? this.subjectId,
      objectId: objectId ?? this.objectId,
      title: title ?? this.title,
      imageId: imageId ?? this.imageId,
      blurHash: blurHash ?? this.blurHash,
      height: height ?? this.height,
      width: width ?? this.width,
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
          ..write('width: $width')
          ..write(')'))
        .toString();
  }
}

class P2pMessages extends Table with TableInfo<P2pMessages, P2pMessagesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  P2pMessages(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
      'client_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
      'server_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
      'sender_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> receiverId = GeneratedColumn<String>(
      'receiver_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> deliveredAt = GeneratedColumn<DateTime>(
      'delivered_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
      'status', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        clientId,
        serverId,
        senderId,
        receiverId,
        content,
        createdAt,
        deliveredAt,
        status
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'p2p_messages';
  @override
  Set<GeneratedColumn> get $primaryKey => {clientId, serverId};
  @override
  P2pMessagesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return P2pMessagesData(
      clientId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}client_id'])!,
      serverId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}server_id'])!,
      senderId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sender_id'])!,
      receiverId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}receiver_id'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      deliveredAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}delivered_at']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}status'])!,
    );
  }

  @override
  P2pMessages createAlias(String alias) {
    return P2pMessages(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
}

class P2pMessagesData extends DataClass implements Insertable<P2pMessagesData> {
  final String clientId;
  final String serverId;
  final String senderId;
  final String receiverId;
  final String content;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final int status;
  const P2pMessagesData(
      {required this.clientId,
      required this.serverId,
      required this.senderId,
      required this.receiverId,
      required this.content,
      required this.createdAt,
      this.deliveredAt,
      required this.status});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_id'] = Variable<String>(clientId);
    map['server_id'] = Variable<String>(serverId);
    map['sender_id'] = Variable<String>(senderId);
    map['receiver_id'] = Variable<String>(receiverId);
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || deliveredAt != null) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt);
    }
    map['status'] = Variable<int>(status);
    return map;
  }

  P2pMessagesCompanion toCompanion(bool nullToAbsent) {
    return P2pMessagesCompanion(
      clientId: Value(clientId),
      serverId: Value(serverId),
      senderId: Value(senderId),
      receiverId: Value(receiverId),
      content: Value(content),
      createdAt: Value(createdAt),
      deliveredAt: deliveredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveredAt),
      status: Value(status),
    );
  }

  factory P2pMessagesData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return P2pMessagesData(
      clientId: serializer.fromJson<String>(json['clientId']),
      serverId: serializer.fromJson<String>(json['serverId']),
      senderId: serializer.fromJson<String>(json['senderId']),
      receiverId: serializer.fromJson<String>(json['receiverId']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      deliveredAt: serializer.fromJson<DateTime?>(json['deliveredAt']),
      status: serializer.fromJson<int>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientId': serializer.toJson<String>(clientId),
      'serverId': serializer.toJson<String>(serverId),
      'senderId': serializer.toJson<String>(senderId),
      'receiverId': serializer.toJson<String>(receiverId),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'deliveredAt': serializer.toJson<DateTime?>(deliveredAt),
      'status': serializer.toJson<int>(status),
    };
  }

  P2pMessagesData copyWith(
          {String? clientId,
          String? serverId,
          String? senderId,
          String? receiverId,
          String? content,
          DateTime? createdAt,
          Value<DateTime?> deliveredAt = const Value.absent(),
          int? status}) =>
      P2pMessagesData(
        clientId: clientId ?? this.clientId,
        serverId: serverId ?? this.serverId,
        senderId: senderId ?? this.senderId,
        receiverId: receiverId ?? this.receiverId,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
        deliveredAt: deliveredAt.present ? deliveredAt.value : this.deliveredAt,
        status: status ?? this.status,
      );
  P2pMessagesData copyWithCompanion(P2pMessagesCompanion data) {
    return P2pMessagesData(
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      receiverId:
          data.receiverId.present ? data.receiverId.value : this.receiverId,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deliveredAt:
          data.deliveredAt.present ? data.deliveredAt.value : this.deliveredAt,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('P2pMessagesData(')
          ..write('clientId: $clientId, ')
          ..write('serverId: $serverId, ')
          ..write('senderId: $senderId, ')
          ..write('receiverId: $receiverId, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(clientId, serverId, senderId, receiverId,
      content, createdAt, deliveredAt, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is P2pMessagesData &&
          other.clientId == this.clientId &&
          other.serverId == this.serverId &&
          other.senderId == this.senderId &&
          other.receiverId == this.receiverId &&
          other.content == this.content &&
          other.createdAt == this.createdAt &&
          other.deliveredAt == this.deliveredAt &&
          other.status == this.status);
}

class P2pMessagesCompanion extends UpdateCompanion<P2pMessagesData> {
  final Value<String> clientId;
  final Value<String> serverId;
  final Value<String> senderId;
  final Value<String> receiverId;
  final Value<String> content;
  final Value<DateTime> createdAt;
  final Value<DateTime?> deliveredAt;
  final Value<int> status;
  const P2pMessagesCompanion({
    this.clientId = const Value.absent(),
    this.serverId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.receiverId = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.status = const Value.absent(),
  });
  P2pMessagesCompanion.insert({
    required String clientId,
    required String serverId,
    required String senderId,
    required String receiverId,
    required String content,
    required DateTime createdAt,
    this.deliveredAt = const Value.absent(),
    required int status,
  })  : clientId = Value(clientId),
        serverId = Value(serverId),
        senderId = Value(senderId),
        receiverId = Value(receiverId),
        content = Value(content),
        createdAt = Value(createdAt),
        status = Value(status);
  static Insertable<P2pMessagesData> custom({
    Expression<String>? clientId,
    Expression<String>? serverId,
    Expression<String>? senderId,
    Expression<String>? receiverId,
    Expression<String>? content,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? deliveredAt,
    Expression<int>? status,
  }) {
    return RawValuesInsertable({
      if (clientId != null) 'client_id': clientId,
      if (serverId != null) 'server_id': serverId,
      if (senderId != null) 'sender_id': senderId,
      if (receiverId != null) 'receiver_id': receiverId,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
      if (deliveredAt != null) 'delivered_at': deliveredAt,
      if (status != null) 'status': status,
    });
  }

  P2pMessagesCompanion copyWith(
      {Value<String>? clientId,
      Value<String>? serverId,
      Value<String>? senderId,
      Value<String>? receiverId,
      Value<String>? content,
      Value<DateTime>? createdAt,
      Value<DateTime?>? deliveredAt,
      Value<int>? status}) {
    return P2pMessagesCompanion(
      clientId: clientId ?? this.clientId,
      serverId: serverId ?? this.serverId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (receiverId.present) {
      map['receiver_id'] = Variable<String>(receiverId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (deliveredAt.present) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('P2pMessagesCompanion(')
          ..write('clientId: $clientId, ')
          ..write('serverId: $serverId, ')
          ..write('senderId: $senderId, ')
          ..write('receiverId: $receiverId, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('status: $status')
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

class DatabaseAtV3 extends GeneratedDatabase {
  DatabaseAtV3(QueryExecutor e) : super(e);
  late final Accounts accounts = Accounts(this);
  late final Friends friends = Friends(this);
  late final P2pMessages p2pMessages = P2pMessages(this);
  late final Settings settings = Settings(this);
  late final Index p2pMessagesSender = Index('p2p_messages_sender',
      'CREATE INDEX p2p_messages_sender ON p2p_messages (sender_id)');
  late final Index p2pMessagesReceiver = Index('p2p_messages_receiver',
      'CREATE INDEX p2p_messages_receiver ON p2p_messages (receiver_id)');
  late final Index p2pMessagesCreatedAt = Index('p2p_messages_created_at',
      'CREATE INDEX p2p_messages_created_at ON p2p_messages (created_at)');
  late final Index p2pMessagesDeliveredAt = Index('p2p_messages_delivered_at',
      'CREATE INDEX p2p_messages_delivered_at ON p2p_messages (delivered_at)');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        accounts,
        friends,
        p2pMessages,
        settings,
        p2pMessagesSender,
        p2pMessagesReceiver,
        p2pMessagesCreatedAt,
        p2pMessagesDeliveredAt
      ];
  @override
  int get schemaVersion => 3;
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}
