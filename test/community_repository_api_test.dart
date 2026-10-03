import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:protrading_ai/data/repositories/community_repository.dart';
import 'package:protrading_ai/core/utils/community_post_link.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'alice';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'offline-token';
}

class _Auth extends Fake implements FirebaseAuth {
  bool signedIn = true;
  @override
  User? get currentUser => signedIn ? _User() : null;
}

class _Firestore extends Fake implements FirebaseFirestore {}

void main() {
  test(
    'Post/comment transport retries preserve IDs and use token-bound APIs',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.headers['Authorization'], 'Bearer offline-token');
        final data = jsonDecode(request.body) as Map<String, dynamic>;
        expect(data.containsKey('userName'), isFalse);
        expect(data.containsKey('userId'), isFalse);
        if (requests.length.isOdd) throw http.ClientException('lost response');
        final key = request.url.path.endsWith('/posts')
            ? 'postId'
            : 'commentId';
        return http.Response(jsonEncode({key: 'a' * 64}), 200);
      });
      addTearDown(client.close);
      var sequence = 0;
      final repository = CommunityRepository(
        firestore: _Firestore(),
        auth: _Auth(),
        client: client,
        operationIdFactory: () => 'operation_12345678_${sequence++}',
      );
      await expectLater(
        repository.createPost(' Market note '),
        throwsA(isA<http.ClientException>()),
      );
      await repository.createPost('Market note');
      await expectLater(
        repository.createComment('post123', ' Public reply '),
        throwsA(isA<http.ClientException>()),
      );
      await repository.createComment('post123', 'Public reply');
      final bodies = requests
          .map((request) => jsonDecode(request.body) as Map<String, dynamic>)
          .toList();
      expect(bodies[0]['requestId'], bodies[1]['requestId']);
      expect(bodies[2]['requestId'], bodies[3]['requestId']);
      expect(bodies[0]['requestId'], isNot(bodies[2]['requestId']));
      expect(requests[0].url.path, '/api/community/posts');
      expect(requests[2].url.path, '/api/community/comments');
      expect(bodies[2]['postId'], 'post123');
    },
  );

  test(
    'Missing identity and invalid comments never write; denial remains an error',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('{}', 403);
      });
      addTearDown(client.close);
      final auth = _Auth();
      final repository = CommunityRepository(
        firestore: _Firestore(),
        auth: auth,
        client: client,
        operationIdFactory: () => 'operation_12345678',
      );
      await expectLater(
        repository.createComment('post123', 'x' * 1001),
        throwsArgumentError,
      );
      auth.signedIn = false;
      await expectLater(repository.createPost('Note'), throwsStateError);
      expect(calls, 0);
      auth.signedIn = true;
      await expectLater(
        repository.createComment('post123', 'Reply'),
        throwsStateError,
      );
      expect(calls, 1);
    },
  );

  test(
    'Share link carries only a validated public post ID and round trips',
    () {
      final link = communityPostLink(
        Uri.parse('https://example.test:8443/?token=private&uid=alice#secret'),
        'post123',
      );
      expect(
        link.toString(),
        'https://example.test:8443/?communityPost=post123',
      );
      expect(sharedCommunityPostId(link), 'post123');
      expect(
        sharedCommunityPostId(
          Uri.parse('https://example.test/?communityPost=../users/alice'),
        ),
        isNull,
      );
      expect(
        sharedCommunityPostId(
          Uri.parse('https://example.test/?communityPost=a&communityPost=b'),
        ),
        isNull,
      );
      expect(
        communityPostLink(Uri.parse('file:///app/index.html'), 'post123').host,
        'protrading-ai-2026.web.app',
      );
      expect(
        () => communityPostLink(Uri.parse('https://example.test'), '../secret'),
        throwsArgumentError,
      );
    },
  );
}
