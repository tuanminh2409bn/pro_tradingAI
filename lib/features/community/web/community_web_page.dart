import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import 'dart:ui';
import '../../../core/constants/colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_cubit.dart';
import '../../../data/models/community_models.dart';
import '../../../data/repositories/community_repository.dart';
import '../bloc/community_bloc.dart';
import '../bloc/community_event.dart';
import '../bloc/community_state.dart';
import 'widgets/community_like_button.dart';
import 'widgets/community_comments_dialog.dart';
import '../../../core/utils/community_post_link.dart';

class CommunityWebPage extends StatefulWidget {
  final VoidCallback? onMenuPressed;
  final String? sharedPostId;
  const CommunityWebPage({super.key, this.onMenuPressed, this.sharedPostId});

  @override
  State<CommunityWebPage> createState() => _CommunityWebPageState();
}

class _CommunityWebPageState extends State<CommunityWebPage> {
  final TextEditingController _postController = TextEditingController();
  int _lastLikeFailureNonce = 0;
  Stream<CommunityPost?>? _sharedPostStream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final postId = widget.sharedPostId;
    if (postId != null) {
      _sharedPostStream ??= context.read<CommunityRepository>().watchPost(
        postId,
      );
    }
  }

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CommunityBloc(
        communityRepository: context.read<CommunityRepository>(),
      )..add(LoadCommunityData()),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            _WebTopNavbar(onMenuPressed: widget.onMenuPressed),
            Expanded(
              child: BlocConsumer<CommunityBloc, CommunityState>(
                listenWhen: (previous, current) =>
                    previous is CommunityLoaded &&
                    current is CommunityLoaded &&
                    (previous.postResultNonce != current.postResultNonce ||
                        previous.likeFailureNonce != current.likeFailureNonce),
                listener: (context, state) {
                  if (state is! CommunityLoaded) return;
                  final language = context.read<LocaleCubit>().state;
                  if (state.likeFailureNonce != _lastLikeFailureNonce) {
                    _lastLikeFailureNonce = state.likeFailureNonce;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.get(
                            language,
                            'community_like_failed',
                          ),
                        ),
                      ),
                    );
                    return;
                  }
                  if (state.postSucceeded) _postController.clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        state.postSucceeded
                            ? AppLocalizations.get(
                                language,
                                'community_post_success',
                              )
                            : AppLocalizations.get(
                                language,
                                'community_post_failed',
                              ),
                      ),
                      backgroundColor: state.postSucceeded
                          ? AppColors.primary
                          : AppColors.bear,
                    ),
                  );
                },
                builder: (context, state) {
                  if (state is CommunityLoading || state is CommunityInitial) {
                    _lastLikeFailureNonce = 0;
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }

                  if (state is CommunityError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.tr(state.message),
                            style: const TextStyle(color: AppColors.bear),
                          ),
                          TextButton(
                            onPressed: () => context.read<CommunityBloc>().add(
                              LoadCommunityData(),
                            ),
                            child: Text(context.tr('community_retry')),
                          ),
                        ],
                      ),
                    );
                  }

                  if (state is CommunityLoaded) {
                    final isNarrow = MediaQuery.sizeOf(context).width < 900;
                    final feed = Column(
                      children: [
                        _buildPostCreationArea(context, state),
                        const SizedBox(height: 32),
                        _buildFeedList(context, state),
                      ],
                    );
                    final leaderboard = _LeaderboardCard(
                      entries: state.leaderboard,
                    );
                    return SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isNarrow ? 24 : 40,
                        vertical: 32,
                      ),
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: isNarrow
                              ? Column(
                                  children: [
                                    feed,
                                    const SizedBox(height: 32),
                                    leaderboard,
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 2, child: feed),
                                    const SizedBox(width: 40),
                                    SizedBox(width: 320, child: leaderboard),
                                  ],
                                ),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostCreationArea(BuildContext context, CommunityLoaded state) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: const Icon(Icons.person, color: Colors.white24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _postController,
                  enabled: !state.isPosting,
                  maxLines: 4,
                  maxLength: communityPostMaxLength,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: context.tr('community_post_hint'),
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    fillColor: const Color(0xFF0b0e11),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox.shrink(),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _postController,
                builder: (context, value, _) {
                  final content = normalizeCommunityPostContent(value.text);
                  final canPost =
                      !state.isPosting && isValidCommunityPostContent(content);
                  return ElevatedButton(
                    onPressed: canPost
                        ? () => context.read<CommunityBloc>().add(
                            CreatePost(content),
                          )
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      context.tr('community_post_button'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeedList(BuildContext context, CommunityLoaded state) {
    final posts = state.posts
        .where((post) => post.id != widget.sharedPostId)
        .toList();
    return Column(
      children: [
        if (widget.sharedPostId != null)
          StreamBuilder<CommunityPost?>(
            stream: _sharedPostStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  children: [
                    Text(
                      context.tr('common_data_unavailable'),
                      style: const TextStyle(color: AppColors.bear),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _sharedPostStream = context
                            .read<CommunityRepository>()
                            .watchPost(widget.sharedPostId!);
                      }),
                      child: Text(context.tr('community_retry')),
                    ),
                  ],
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                );
              }
              final post = snapshot.data;
              if (post == null) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    context.tr('community_post_unavailable'),
                    style: const TextStyle(color: Colors.white54),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('community_shared_post'),
                    style: const TextStyle(color: AppColors.primary),
                  ),
                  const SizedBox(height: 12),
                  _PostCard(
                    post: post,
                    liked: state.likedPostIds.contains(post.id),
                    liking: state.likingPostIds.contains(post.id),
                  ),
                ],
              );
            },
          ),
        _buildPosts(context, state, posts),
      ],
    );
  }

  Widget _buildPosts(
    BuildContext context,
    CommunityLoaded state,
    List<CommunityPost> posts,
  ) {
    if (posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            context.tr('community_feed_empty'),
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: posts.length,
      itemBuilder: (context, index) => _PostCard(
        post: posts[index],
        liked: state.likedPostIds.contains(posts[index].id),
        liking: state.likingPostIds.contains(posts[index].id),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final CommunityPost post;
  final bool liked;
  final bool liking;
  const _PostCard({
    required this.post,
    required this.liked,
    required this.liking,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('community-post-${post.id}'),
      margin: const EdgeInsets.only(bottom: 24),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white10,
                          ),
                          child: const Icon(
                            Icons.person,
                            size: 20,
                            color: Colors.white24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  post.userName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (post.isVerified)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4.0),
                                    child: Icon(
                                      Icons.verified,
                                      size: 14,
                                      color: AppColors.primary,
                                    ),
                                  ),
                              ],
                            ),
                            Text(
                              post.hasVerifiedTrade
                                  ? '${_postTime(context, post).toUpperCase()} • ${post.tradeInfo}'
                                  : _postTime(context, post).toUpperCase(),
                              style: TextStyle(
                                fontSize: 8,
                                color: post.hasVerifiedTrade
                                    ? (post.isProfit
                                          ? AppColors.primary
                                          : AppColors.bear)
                                    : Colors.white38,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (post.hasVerifiedTrade)
                      _buildProfitBlur(context, post.profit, post.isProfit),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  post.content,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                if (post.chartImageUrl != null)
                  Container(
                    height: 300,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      image: post.chartImageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(post.chartImageUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: null,
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            color: Colors.white.withValues(alpha: 0.02),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (post.id != null)
                  CommunityLikeButton(
                    postId: post.id!,
                    count: post.likes,
                    liked: liked,
                    busy: liking,
                    onLike: () => context.read<CommunityBloc>().add(
                      LikeCommunityPost(post.id!),
                    ),
                  )
                else
                  _buildMetric(
                    context,
                    Icons.thumb_up,
                    context.tr('community_likes'),
                    post.likes,
                  ),
                if (post.id != null)
                  TextButton.icon(
                    key: ValueKey('community-comments-${post.id}'),
                    onPressed: () => showCommunityComments(context, post.id!),
                    icon: const Icon(Icons.forum_outlined, size: 18),
                    label: Text(
                      '${context.tr('community_comments')} · ${post.comments}',
                    ),
                  )
                else
                  _buildMetric(
                    context,
                    Icons.forum,
                    context.tr('community_comments'),
                    post.comments,
                  ),
                if (post.id != null)
                  TextButton.icon(
                    key: ValueKey('community-share-${post.id}'),
                    onPressed: () async {
                      var succeeded = false;
                      try {
                        await Clipboard.setData(
                          ClipboardData(
                            text: communityPostLink(
                              Uri.base,
                              post.id!,
                            ).toString(),
                          ),
                        );
                        succeeded = true;
                      } catch (_) {
                        succeeded = false;
                      }
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppLocalizations.get(
                              context.read<LocaleCubit>().state,
                              succeeded
                                  ? 'community_share_copied'
                                  : 'community_share_failed',
                            ),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.link, size: 18),
                    label: Text(context.tr('community_share_link')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitBlur(BuildContext context, double value, bool isPositive) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Text(
                '${isPositive ? '+' : ''}\$${value.abs().toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isPositive ? AppColors.primary : AppColors.bear,
                ),
              ),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ],
          ),
        ),
        Text(
          context.tr('community_profit_hidden').toUpperCase(),
          style: const TextStyle(
            fontSize: 8,
            color: Colors.white24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildMetric(
    BuildContext context,
    IconData icon,
    String label,
    int value,
  ) {
    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white38),
            const SizedBox(width: 6),
            Text(
              '$value',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _postTime(BuildContext context, CommunityPost post) =>
      post.timeAgo == '__TIME_UNAVAILABLE__'
      ? context.tr('community_time_unavailable')
      : post.timeAgo;
}

class _LeaderboardCard extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  const _LeaderboardCard({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('community_leaderboard_title').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                Text(
                  context.tr('community_top_rankings').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 8,
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.tr('community_leaderboard_empty'),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            )
          else
            ...entries.map(
              (entry) => _buildLeaderRow(
                context,
                entry.rank,
                entry.name,
                '${entry.performance >= 0 ? '+' : ''}${entry.performance.toStringAsFixed(1)}%',
                entry.volume,
                entry.rank == 1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLeaderRow(
    BuildContext context,
    int rank,
    String name,
    String perf,
    String vol,
    bool isFirst,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.02)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: isFirst ? AppColors.primary : Colors.white24,
              ),
            ),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.white10,
            ),
            child: const Icon(Icons.person, size: 16, color: Colors.white10),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${context.tr('community_volume').toUpperCase()}: $vol',
                  style: const TextStyle(fontSize: 8, color: Colors.white38),
                ),
              ],
            ),
          ),
          Text(
            perf,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _WebTopNavbar extends StatelessWidget {
  final VoidCallback? onMenuPressed;
  const _WebTopNavbar({this.onMenuPressed});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF111417),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          if (onMenuPressed != null)
            IconButton(
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
              onPressed: onMenuPressed,
              icon: const Icon(Icons.menu, color: Colors.white, size: 20),
            ),
          const Text(
            'KINETIC',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () =>
                context.read<AuthBloc>().add(AuthLogoutRequested()),
            icon: const Icon(Icons.logout, color: AppColors.bear, size: 20),
          ),
        ],
      ),
    );
  }
}
