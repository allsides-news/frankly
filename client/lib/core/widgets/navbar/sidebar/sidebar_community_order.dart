import 'package:data_models/community/community.dart';

/// Pins [currentCommunityId] at the front of the sidebar list.
/// Returns [communities] unchanged when the id is null or not in the list.
List<Community> orderCommunitiesForSidebar(
  List<Community> communities, {
  String? currentCommunityId,
}) {
  if (currentCommunityId == null) {
    return List<Community>.of(communities);
  }
  final currentIndex =
      communities.indexWhere((community) => community.id == currentCommunityId);
  if (currentIndex < 0) {
    return List<Community>.of(communities);
  }
  final currentCommunity = communities[currentIndex];
  return [
    currentCommunity,
    ...communities.where((community) => community.id != currentCommunityId),
  ];
}
