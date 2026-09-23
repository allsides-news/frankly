import 'dart:async';
import 'dart:convert';

import 'package:firebase_admin_interop/firebase_admin_interop.dart';
import 'package:firebase_functions_interop/firebase_functions_interop.dart'
    hide CloudFunction;
import '../cloud_function.dart';
import '../utils/infra/firebase_auth_utils.dart';
import '../utils/infra/firestore_utils.dart';
import 'package:data_models/admin/partner_agreement.dart';
import 'package:data_models/community/community.dart';
import 'package:data_models/community/community_tag.dart';
import 'package:data_models/community/community_tag_definition.dart';
import 'package:data_models/community/membership.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/utils/utils.dart';

/// Error with an HTTP status code so validation failures return proper
/// 4xx responses instead of a generic 500.
class _ApiException implements Exception {
  final int statusCode;
  final String message;

  _ApiException(this.statusCode, this.message);
}

/// HTTP endpoint (POST + JSON) for creating a Space (community) from outside
/// the app, e.g. curl or another backend.
///
/// Mirrors the `createCommunity` onCall flow in create_community.dart
/// (community doc + owner membership + partner agreement) but takes the
/// owner's user ID from the payload instead of the Firebase Auth context,
/// and additionally applies tags (community-tag-definitions lookup/create +
/// community-tags subcollection docs, mirroring FirestoreTagService on the
/// client).
///
/// Auth: requires an `x-api-key` header matching the
/// `app.create_space_api_key` functions config value. Fails closed (503) if
/// the key is not configured.
///
/// Example payload: see scripts/create-space-example.json
class CreateCommunityApi implements CloudFunction {
  @override
  final String functionName = 'createCommunityApi';

  String get _configuredApiKey =>
      functions.config.get('app.create_space_api_key') as String? ?? '';

  Future<void> _sendJson(
    ExpressHttpRequest expressRequest,
    int statusCode,
    Map<String, dynamic> body,
  ) async {
    expressRequest.response.statusCode = statusCode;
    expressRequest.response.headers.set('Content-Type', 'application/json');
    expressRequest.response.write(jsonEncode(body));
    await expressRequest.response.close();
  }

  Future<void> expressAction(ExpressHttpRequest expressRequest) async {
    expressRequest.response.headers.set('Access-Control-Allow-Origin', '*');

    if (expressRequest.method == 'OPTIONS') {
      expressRequest.response.headers
          .set('Access-Control-Allow-Methods', 'POST');
      expressRequest.response.headers
          .set('Access-Control-Allow-Headers', 'Content-Type, x-api-key');
      expressRequest.response.headers.set('Access-Control-Max-Age', '3600');
      expressRequest.response.statusCode = 204;
      await expressRequest.response.close();
      return;
    }

    try {
      if (expressRequest.method != 'POST') {
        throw _ApiException(405, 'Use POST with a JSON body.');
      }

      // Fail closed: refuse all requests until an API key is configured via
      // `firebase functions:config:set app.create_space_api_key="..."`.
      final configuredKey = _configuredApiKey;
      if (configuredKey.isEmpty) {
        throw _ApiException(503, 'API key is not configured on the server.');
      }
      final providedKey = expressRequest.headers.value('x-api-key') ?? '';
      if (providedKey != configuredKey) {
        throw _ApiException(401, 'Invalid or missing x-api-key header.');
      }

      dynamic body = expressRequest.body;
      if (body is String && body.isNotEmpty) {
        // Reached when Express didn't parse the body (non-JSON content
        // type); a decode failure is client error, not a 500.
        try {
          body = jsonDecode(body);
        } on FormatException catch (e) {
          throw _ApiException(400, 'Request body is not valid JSON: $e');
        }
      }
      if (body is! Map) {
        throw _ApiException(400, 'Request body must be a JSON object.');
      }

      final result = await _createSpace(Map<String, dynamic>.from(body));
      await _sendJson(expressRequest, 201, result);
    } on _ApiException catch (e) {
      await _sendJson(expressRequest, e.statusCode, {'error': e.message});
    } catch (e, stacktrace) {
      print('Error in $functionName');
      print(e);
      print(stacktrace);
      await _sendJson(
        expressRequest,
        500,
        {'error': 'Internal error creating space: $e'},
      );
    }
  }

  /// Returns json[key] as a trimmed string (null when absent). Throws 400 on
  /// wrong types so bad client input doesn't surface as a 500 from a cast.
  String? _stringField(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw _ApiException(400, 'Field "$key" must be a string.');
    }
    return value.trim();
  }

  Future<Map<String, dynamic>> _createSpace(Map<String, dynamic> json) async {
    final ownerUserId = _stringField(json, 'ownerUserId') ?? '';
    if (ownerUserId.isEmpty) {
      throw _ApiException(400, 'ownerUserId is required.');
    }

    final name = _stringField(json, 'name') ?? '';
    if (name.isEmpty) {
      throw _ApiException(400, 'name is required.');
    }

    // Verify the owner exists in Firebase Auth before creating anything.
    try {
      await firebaseAuthUtils.getUser(ownerUserId);
    } catch (_) {
      throw _ApiException(
        400,
        'No Firebase Auth user found for ownerUserId "$ownerUserId".',
      );
    }

    // Same displayId rules as the create dialog (create_community_dialog.dart).
    final displayId = _stringField(json, 'displayId') ?? '';
    if (displayId.isNotEmpty &&
        !RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(displayId)) {
      throw _ApiException(
        400,
        'displayId can only contain letters, numbers, and dashes.',
      );
    }

    final contactEmail = _stringField(json, 'contactEmail') ?? '';
    if (contactEmail.isNotEmpty &&
        !RegExp(r'^\S+@\S+\.\S+$').hasMatch(contactEmail)) {
      throw _ApiException(400, 'contactEmail is not a valid email address.');
    }

    final makePrivateRaw = json['makePrivate'];
    if (makePrivateRaw is! bool?) {
      throw _ApiException(400, 'Field "makePrivate" must be a boolean.');
    }
    final makePrivate = makePrivateRaw ?? false;

    final tagsRaw = json['tags'];
    if (tagsRaw is! List? || (tagsRaw?.any((tag) => tag is! String) ?? false)) {
      throw _ApiException(400, 'Field "tags" must be an array of strings.');
    }
    final tags = (tagsRaw ?? [])
        .cast<String>()
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();

    final communityCollection = firestore.collection('/community/');
    final communityDocRef = communityCollection.document();

    // Dialog stores the provided casing plus a lowercase variant.
    final displayIds = displayId.isEmpty
        ? [communityDocRef.documentID]
        : {displayId, displayId.toLowerCase()}.toList();

    final community = Community(
      id: communityDocRef.documentID,
      name: name,
      creatorId: ownerUserId,
      isPublic: !makePrivate,
      tagLine: _stringField(json, 'tagLine'),
      // "About" section is stored as `description` on the community doc.
      description: _stringField(json, 'about'),
      contactEmail: contactEmail.isEmpty ? null : contactEmail,
      profileImageUrl: _stringField(json, 'logoUrl') ??
          'https://picsum.photos/seed/${communityDocRef.documentID}-profile/512',
      bannerImageUrl: _stringField(json, 'bannerImageUrl') ?? '',
      // Null theme colors = app default color preset.
      themeLightColor: _stringField(json, 'themeLightColor'),
      themeDarkColor: _stringField(json, 'themeDarkColor'),
      communitySettings: const CommunitySettings(),
      eventSettings: EventSettings.defaultSettings,
      displayIds: displayIds,
    );

    final agreementRef = firestore.collection('partner-agreements').document();
    final agreement = PartnerAgreement(
      id: agreementRef.documentID,
      communityId: communityDocRef.documentID,
      allowPayments: true,
    );
    final agreementFields = [
      PartnerAgreement.kFieldId,
      PartnerAgreement.kFieldCommunityId,
      PartnerAgreement.kFieldAllowPayments,
    ];

    // The displayId uniqueness check runs inside the transaction (getQuery
    // holds pessimistic locks) so two concurrent requests can't both claim the
    // same vanity URL. The conflict is captured in a variable instead of
    // thrown: exceptions from this callback cross a Dart->JS promise boundary
    // and may not surface with their type intact.
    _ApiException? displayIdConflict;
    await firestore.runTransaction((transaction) async {
      displayIdConflict = null; // Reset in case the transaction retries.

      // Reads must precede writes within a Firestore transaction.
      if (displayId.isNotEmpty) {
        for (final id in displayIds) {
          final matching = await transaction.getQuery(
            communityCollection.where(
              Community.kFieldDisplayIds,
              arrayContains: id,
            ),
          );
          if (matching.isNotEmpty) {
            displayIdConflict = _ApiException(
              409,
              'The URL display name "$id" is already taken.',
            );
            return;
          }
        }
      }

      transaction.set(
        communityDocRef,
        DocumentData.fromMap(
          firestoreUtils.toFirestoreJson(community.toJson()),
        ),
      );

      transaction.set(
        firestore.document(
          'memberships/$ownerUserId/community-membership/${communityDocRef.documentID}',
        ),
        DocumentData.fromMap(
          firestoreUtils.toFirestoreJson(
            Membership(
              communityId: communityDocRef.documentID,
              userId: ownerUserId,
              status: MembershipStatus.owner,
            ).toJson(),
          ),
        ),
      );

      transaction.set(
        agreementRef,
        DocumentData.fromMap(
          jsonSubset(
            agreementFields,
            firestoreUtils.toFirestoreJson(agreement.toJson()),
          ),
        ),
        merge: true,
      );
    });

    if (displayIdConflict != null) {
      throw displayIdConflict!;
    }

    // Tags are applied after the space is committed, so a tag failure must not
    // fail the request: the space already exists and a retried request would
    // create a duplicate. Failed tags are reported in `tagsFailed` instead.
    final tagsApplied = <String>[];
    final tagsFailed = <String>[];
    for (final title in tags) {
      try {
        await _applyTag(communityId: communityDocRef.documentID, title: title);
        tagsApplied.add(title);
      } catch (e) {
        print(
          'Failed to apply tag "$title" to ${communityDocRef.documentID}: $e',
        );
        tagsFailed.add(title);
      }
    }

    return {
      'communityId': communityDocRef.documentID,
      'displayId': displayIds.first,
      'spacePath': '/space/${displayIds.first}',
      'tagsApplied': tagsApplied,
      if (tagsFailed.isNotEmpty) 'tagsFailed': tagsFailed,
    };
  }

  /// Looks up (by exact title) or creates a tag definition, then tags the
  /// community with it. Mirrors FirestoreTagService.lookupOrCreateTagDefinition
  /// and addCommunityTag on the client.
  Future<void> _applyTag({
    required String communityId,
    required String title,
  }) async {
    final definitionsCollection =
        firestore.collection('community-tag-definitions');

    String definitionId;
    final existing =
        await definitionsCollection.where('title', isEqualTo: title).get();
    if (existing.isNotEmpty) {
      definitionId = existing.documents.first.documentID;
    } else {
      final definitionRef = definitionsCollection.document();
      definitionId = definitionRef.documentID;
      final definition = CommunityTagDefinition(
        id: definitionId,
        title: title,
        // Same normalization as FirestoreTagService.normalizeSuggestionKey.
        searchKey: title.replaceAll(RegExp(r'[^\w\s]+'), '').toLowerCase(),
      );
      await definitionRef.setData(
        DocumentData.fromMap(
          firestoreUtils.toFirestoreJson(definition.toJson()),
        ),
      );
    }

    final tag = CommunityTag(
      taggedItemType: TaggedItemType.community,
      definitionId: definitionId,
      communityId: communityId,
      taggedItemId: communityId,
    );
    await firestore
        .document('community/$communityId/community-tags/$definitionId')
        .setData(
          DocumentData.fromMap(firestoreUtils.toFirestoreJson(tag.toJson())),
        );
  }

  @override
  void register(FirebaseFunctions functions) {
    functions[functionName] = functions
        .runWith(
          RuntimeOptions(timeoutSeconds: 60, memory: '1GB', minInstances: 0),
        )
        .https
        .onRequest(expressAction);
  }
}
