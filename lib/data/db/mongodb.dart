import 'dart:async';
import 'dart:io';

import 'package:akali/data/models/results.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';
import 'package:ulid/ulid.dart';

import 'package:akali/models.dart';
import 'package:akali/data/auth/auth.dart';

// import 'package:dson/dson.dart';

/// Akali's default database implementation, using MongoDB
class AkaliMongoDatabase implements AkaliDatabase {
  static const _picCollectionName = "pic";
  static const _pendingPicCollectionName = "pendingPic";
  static const _userDataCollectionName = "user";
  static const _tokenCollectionName = "token";
  static const _authCodeCollectionName = "authCode";
  static const _clientCollectionName = "client";

  bool _initialized = false;

  Logger logger;

  Db db;
  String uri;
  // Configuration config;

  DbCollection picCollection;
  DbCollection pendingPicCollection;
  DbCollection userCollection;
  DbCollection tokenCollection;
  DbCollection authCodeCollection;
  DbCollection clientCollection;

  static String databaseType = "MongoDB";
  // static String _dbPrefix = "[$databaseType]";

  /// Connect to MongoDB at [uri].
  ///
  /// Remember to call [init] after creating a new [AkaliMongoDatabase] instance.
  AkaliMongoDatabase(this.uri) {
    assert(this.uri != null);
    // A simple check for valid mongodb address and fixes if it's not
    if (!uri.startsWith('mongodb://')) uri = 'mongodb://' + uri;
    this.logger = new Logger("mongodb");
  }

  /// Initialize database connection.
  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    int tryTimes = 0;
    const maxTryTimes = 5;

    db = new Db(uri);

    while (tryTimes < maxTryTimes) {
      logger.info("Connecting to $uri");
      try {
        await db.open();
        break;
      } catch (e, stacktrace) {
        logger.warning("Unable to connect with $uri", e, stacktrace);
        await Future.delayed(Duration(seconds: 1));
        tryTimes++;
      }
    }
    if (tryTimes >= maxTryTimes) {
      throw ConnectionException("Unable to connect to $uri");
    }
    logger.info("Connected to $uri.");

    // Initialize collections
    picCollection = db.collection(_picCollectionName);
    pendingPicCollection = db.collection(_pendingPicCollectionName);
    userCollection = db.collection(_userDataCollectionName);
    tokenCollection = db.collection(_tokenCollectionName);
    clientCollection = db.collection(_clientCollectionName);
    authCodeCollection = db.collection(_authCodeCollectionName);
  }

  /// Post a new image to database. Returns the written confirmation.
  Future<void> postImageData(Pic pic) async {
    var map = await picCollection.insert(pic.asMap());
    return map;
  }

  /// Search for image(s) meeting the criteria [crit].
  Future<SearchResult<Pic>> queryImg(
    ImageSearchCriteria crit, {
    int limit = 20,
    int skip = 0,
  }) async {
    var query = where;

    logger.fine("Query image $crit");

    if (crit.tags != null) query = query.all('tags', crit.tags);
    if (crit.authors != null) query = query.all('author', crit.authors);
    if (crit.height != null) {
      if (crit.height.max != null)
        query = query.inRange('height', crit.height.min, crit.height.max,
            maxInclude: true);
      else
        query = query.all('height', [crit.height.min]);
    }
    if (crit.width != null) {
      if (crit.width.max != null)
        query = query.inRange('width', crit.width.min, crit.width.max,
            maxInclude: true);
      else
        query = query.all('height', [crit.width.min]);
    }

    query = query.limit(limit).skip(skip);

    List<Pic> result = await (await picCollection.find(query))
        .map<Pic>((item) => Pic.fromMap(item))
        .toList();

    return SearchResult()..result = result;
  }

  /// Find **the** picture with this [id].
  ///
  /// Preferably used when viewing specific pictures.
  Future<Pic> queryImgID(String id) async {
    logger.fine("Query image #$id");
    var result =
        await picCollection.findOne(where.id(ObjectId.fromHexString(id)));
    if (result == null)
      throw ArgumentError.value(id);
    else
      return Pic.fromMap(result);
  }

  Future<ActionResult<Pic>> updateImgInfo(Pic newInfo, String id) async {
    var _id = ObjectId.fromHexString(id);
    newInfo.id = _id;
    var result =
        await picCollection.update(where.id(_id), newInfo.asDatabaseMap());
    newInfo.id = _id;
    bool success = (result['n'] ?? 0) > 0;
    if (success)
      return ActionResult()
        ..success = true
        ..data = newInfo
        ..affected = result['n'];
    else
      throw ArgumentError.value(newInfo, "newInfo", result);
  }

  /// Adds an image with link [blobLink] and no info related
  /// to [pendingImageCollection]
  Future<String> addPendingImage(String blobLink) async {
    ObjectId id = ObjectId();
    await pendingPicCollection.insert({
      '_id': id,
      'link': blobLink + '/' + id.toHexString() + '.png',
    });
    return id.toHexString();
  }

  @override
  FutureOr<ActionResult<Pic>> createImg(Pic img) async {
    var id = img.id ?? new ObjectId();
    var result =
        await picCollection.update(where.id(id), img.asMap(), upsert: true);
    int nAffected = result['nModified'] + result['nUpserted'];
    img.id = id;
    if (nAffected != 0)
      return ActionResult()
        ..affected = nAffected
        ..data = img
        ..success = true;
    else
      return ActionResult()
        ..success = false
        ..message = (result['writeError'] ??
                result['writeConcernError'] ??
                "Task Failed Successfully")
            .toString();
  }

  @override
  FutureOr<ActionResult<ObjectId>> createImgId(ObjectId id) async {
    var result = await picCollection.insert({"_id": id});
    if (result['nInserted'] ?? 0 > 0)
      return ActionResult()
        ..data = id
        ..affected = 1
        ..success = true;
    else
      return ActionResult()
        ..success = false
        ..message = (result['writeError'] ??
                result['writeConcernError'] ??
                "Task Failed Successfully")
            .toString();
  }

  Future addInfoToPendingImage(Pic info) async {
    // TODO: implement addInfoToPendingImage
    return null;
  }

  Future<ActionResult> deleteImg(String id) async {
    var result =
        await picCollection.remove(where.id(ObjectId.fromHexString(id)));
    if (result['nDeleted'] != null && result['nDeleted'] > 0)
      return ActionResult()
        ..success = true
        ..affected = result['nDeleted'];
    else
      return ActionResult()
        ..success = false
        ..affected = 0;
  }

  // =============

  FutureOr<void> addToken(AuthToken token, {AuthCode issuedFrom}) async {
    final serializableToken = SeriManagedToken.fromToken(token);
    final map = serializableToken.asMongoDBEntry();
    if (issuedFrom != null) {
      map['issuedFrom'] = issuedFrom.code;
    }
    await tokenCollection.insert(map);
  }

  FutureOr<bool> checkToken(String accessToken) async {
    // TODO: implement checkToken
    return null;
  }

  FutureOr<void> removeToken(String token) async {
    await tokenCollection.remove(where.eq('accessToken', token));
  }

  FutureOr<void> removeAllTokens(int resourceOwnerID) async {
    await tokenCollection.remove(where.eq('resourceOwner', resourceOwnerID));
  }

  FutureOr<AkaliUser> addUser(AkaliUser user) async {
    await userCollection.insert(user.asMap());
    return AkaliUser.fromMap(
        await userCollection.findOne(where.eq("username", user.username)));
  }

  FutureOr<AkaliUser> getUser(String username) async {
    return AkaliUser.fromMap(
        await userCollection.findOne(where.eq("username", username)));
  }

  FutureOr<void> deleteUser(String username) async {
    await userCollection.remove(where.eq('username', username));
  }

  FutureOr<void> deleteUserById(String id) async {
    await userCollection.remove(where.id(ObjectId.fromHexString(id)));
  }

  FutureOr<AkaliUser> changeUserInfo(int id, Map<String, dynamic> info) async {
    // TODO: implement changeUserInfo
    return null;
  }

  @override
  FutureOr<AuthClient> addClient(AuthClient client) async {
    await clientCollection
        .insert(SeriAuthClient.fromClient(client).asMongoDBEntry());
    return client;
  }

  @override
  FutureOr<void> addCode(AuthCode code) async {
    await authCodeCollection
        .insert(SeriManagedToken.fromCode(code).asMongoDBEntry());
    return null;
  }

  @override
  FutureOr<AuthCode> getCode(String code) async {
    return SeriManagedToken.readFromMap(
            await authCodeCollection.findOne(where.eq('code', code)))
        .asAuthCode();
  }

  // TODO: this thing definitely needs optimization... or does it?
  FutureOr<AuthToken> getTokenByAccessToken(String accessToken) async {
    return SeriManagedToken.readFromMap(
            await tokenCollection.findOne(where.eq('accessToken', accessToken)))
        .asToken();
  }

  @override
  FutureOr<AuthToken> getTokenByRefreshToken(String refreshToken) async {
    return SeriManagedToken.readFromMap(await tokenCollection
            .findOne(where.eq('refreshToken', refreshToken)))
        .asToken();
  }

  @override
  FutureOr<AkaliUser> getUserById(String id) {
    // TODO: implement getUserById
    return null;
  }

  @override
  FutureOr<AuthClient> getClient(String clientID) async {
    final result = await clientCollection.aggregate([
      {
        "\$match": {"id": clientID}
      },
      {
        "\$lookup": {
          "localField": "tokenIDs",
          "from": _tokenCollectionName,
          "foreignField": "id",
          "as": "tokenMaps",
        }
      }
    ], allowDiskUse: true);
    if (result['result'] is List && (result['result'] as List).length == 1) {
      return SeriAuthClient.readFromMap(
              result['result'][0] as Map<String, dynamic>)
          .asClient();
    }
    throw ArgumentError.value(clientID);
  }

  @override
  FutureOr<void> removeClient(String clientID) async {
    final client = await clientCollection.findOne(where.eq('id', clientID));
    final tokens = client['tokenIDs'] as List<String>;
    await tokenCollection.remove(where.oneFrom('id', tokens));
    await authCodeCollection.remove(where.oneFrom('id', tokens));
    await clientCollection.remove(where.eq('id', clientID));
    return null;
  }

  @override
  FutureOr<void> removeCode(String code) async {
    await authCodeCollection.remove(where.eq('code', code));
  }

  @override
  FutureOr<void> removeTokenByCode(AuthCode code) async {
    await tokenCollection.remove(where.eq('code', code));
    return null;
  }

  @override
  FutureOr<void> updateToken(String oldToken, String newToken,
      DateTime newIssueDate, DateTime newExpirationDate) async {
    await tokenCollection.findAndModify(
      query: where.eq('accessToken', oldToken),
      update: {
        "accessToken": newToken,
        "issueDate": newIssueDate,
        "expirationDate": newExpirationDate,
      },
    );
  }
}
