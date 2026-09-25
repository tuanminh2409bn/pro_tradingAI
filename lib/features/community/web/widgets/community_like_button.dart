import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';

class CommunityLikeButton extends StatelessWidget {
  final String postId;
  final int count;
  final bool liked;
  final bool busy;
  final VoidCallback onLike;

  const CommunityLikeButton({
    super.key,
    required this.postId,
    required this.count,
    required this.liked,
    required this.busy,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: ValueKey('community-like-$postId'),
      onPressed: liked || busy ? null : onLike,
      icon: Icon(liked ? Icons.thumb_up : Icons.thumb_up_outlined, size: 18),
      label: Text(
        '${context.tr(liked ? 'community_liked' : 'community_like_action')} · $count',
      ),
    );
  }
}
