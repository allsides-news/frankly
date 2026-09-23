import 'package:client/features/user/data/services/user_data_service.dart';
import 'package:client/features/user/data/services/user_service.dart';
import 'package:data_models/community/membership.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import '../../../../../mocked_classes.mocks.dart';

void main() {
  late MockUserService mockUserService;

  setUp(() {
    mockUserService = MockUserService();
    GetIt.instance.registerSingleton<UserService>(mockUserService);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  test('getMembership returns nonmember when there is no signed-in user', () {
    when(mockUserService.currentUserId).thenReturn(null);

    final membership = UserDataService().getMembership('community-1');

    expect(membership.userId, isEmpty);
    expect(membership.communityId, 'community-1');
    expect(membership.status, MembershipStatus.nonmember);
  });
}
