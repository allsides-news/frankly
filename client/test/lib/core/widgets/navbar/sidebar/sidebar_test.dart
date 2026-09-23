import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/core/utils/provider_utils.dart';
import 'package:client/core/widgets/navbar/sidebar/sidebar_community_order.dart';
import 'package:data_models/community/community.dart';
import 'package:provider/provider.dart';

class _CommunityId {
  _CommunityId(this.id);
  final String id;
}

void main() {
  Community community(String id) => Community(id: id, name: id);

  List<Community> orderFromContext(BuildContext context) {
    return orderCommunitiesForSidebar(
      [community('a'), community('b'), community('c')],
      currentCommunityId: watchProviderOrNull<_CommunityId>(context)?.id,
    );
  }

  group('orderCommunitiesForSidebar', () {
    test('returns a copy when current community id is null', () {
      final communities = [community('a'), community('b')];

      final ordered = orderCommunitiesForSidebar(
        communities,
        currentCommunityId: null,
      );

      expect(ordered.map((c) => c.id), ['a', 'b']);
      expect(identical(ordered, communities), isFalse);
    });

    test('puts the current community first', () {
      final ordered = orderCommunitiesForSidebar(
        [community('a'), community('b'), community('c')],
        currentCommunityId: 'b',
      );

      expect(ordered.map((c) => c.id), ['b', 'a', 'c']);
    });

    test('leaves order unchanged when current id is not in the list', () {
      final ordered = orderCommunitiesForSidebar(
        [community('a'), community('b')],
        currentCommunityId: 'missing',
      );

      expect(ordered.map((c) => c.id), ['a', 'b']);
    });

    test('does not duplicate the current community', () {
      final ordered = orderCommunitiesForSidebar(
        [community('a'), community('b')],
        currentCommunityId: 'a',
      );

      expect(ordered.map((c) => c.id), ['a', 'b']);
    });
  });

  group('sidebar CommunityProvider lookup', () {
    testWidgets(
        'missing provider does not throw and leaves community order unchanged',
        (tester) async {
      late List<String> ids;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ids = orderFromContext(context).map((c) => c.id).toList();
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(ids, ['a', 'b', 'c']);
    });

    testWidgets('present provider pins that community first', (tester) async {
      late List<String> ids;

      await tester.pumpWidget(
        Provider<_CommunityId>.value(
          value: _CommunityId('b'),
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                ids = orderFromContext(context).map((c) => c.id).toList();
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(ids, ['b', 'a', 'c']);
    });
  });
}
