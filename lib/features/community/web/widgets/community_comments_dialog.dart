import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../data/models/community_models.dart';
import '../../bloc/community_bloc.dart';
import '../../bloc/community_event.dart';
import '../../bloc/community_state.dart';

Future<void> showCommunityComments(BuildContext context, String postId) async {
  final bloc = context.read<CommunityBloc>();
  bloc.add(OpenCommunityComments(postId));
  await showDialog<void>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: bloc,
      child: CommunityCommentsDialog(postId: postId),
    ),
  );
  if (!bloc.isClosed) bloc.add(const CloseCommunityComments());
}

class CommunityCommentsDialog extends StatefulWidget {
  final String postId;
  const CommunityCommentsDialog({super.key, required this.postId});
  @override
  State<CommunityCommentsDialog> createState() =>
      _CommunityCommentsDialogState();
}

class _CommunityCommentsDialogState extends State<CommunityCommentsDialog> {
  final _controller = TextEditingController();
  late final int _initialResultNonce;

  @override
  void initState() {
    super.initState();
    final current = context.read<CommunityBloc>().state;
    _initialResultNonce = current is CommunityLoaded
        ? current.commentResultNonce
        : 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColors.surface,
    insetPadding: const EdgeInsets.all(16),
    child: SizedBox(
      width: 580,
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: BlocConsumer<CommunityBloc, CommunityState>(
          listenWhen: (previous, current) =>
              previous is CommunityLoaded &&
              current is CommunityLoaded &&
              current.commentsPostId == widget.postId &&
              previous.commentResultNonce != current.commentResultNonce,
          listener: (context, state) {
            final loaded = state as CommunityLoaded;
            if (loaded.commentSucceeded) _controller.clear();
          },
          builder: (context, state) {
            final loaded =
                state is CommunityLoaded &&
                    state.commentsPostId == widget.postId
                ? state
                : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('community_comments'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('community_close'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                Text(
                  context.tr('community_comments_recent'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Expanded(child: _comments(context, state, loaded)),
                const SizedBox(height: 12),
                if (loaded != null &&
                    loaded.commentResultNonce > _initialResultNonce)
                  Text(
                    context.tr(
                      loaded.commentSucceeded
                          ? 'community_comment_success'
                          : 'community_comment_failed',
                    ),
                    style: TextStyle(
                      color: loaded.commentSucceeded
                          ? AppColors.primary
                          : AppColors.bear,
                    ),
                  ),
                TextField(
                  key: const ValueKey('community-comment-draft'),
                  controller: _controller,
                  enabled:
                      loaded != null &&
                      !loaded.isCommenting &&
                      !loaded.commentsError,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: communityCommentMaxLength,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: context.tr('community_comment_hint'),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) {
                    final content = value.text.trim();
                    final canSend =
                        loaded != null &&
                        !loaded.isCommenting &&
                        !loaded.commentsLoading &&
                        !loaded.commentsError &&
                        content.isNotEmpty &&
                        content.length <= communityCommentMaxLength;
                    return FilledButton(
                      key: const ValueKey('community-comment-send'),
                      onPressed: canSend
                          ? () => context.read<CommunityBloc>().add(
                              CreateCommunityComment(widget.postId, content),
                            )
                          : null,
                      child: Text(
                        context.tr(
                          loaded?.isCommenting == true
                              ? 'community_comment_sending'
                              : 'community_comment_send',
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _comments(
    BuildContext context,
    CommunityState state,
    CommunityLoaded? loaded,
  ) {
    if (state is CommunityError || loaded?.commentsError == true) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr('common_data_unavailable'),
              style: const TextStyle(color: AppColors.bear),
            ),
            if (loaded != null)
              TextButton(
                onPressed: () => context.read<CommunityBloc>().add(
                  OpenCommunityComments(widget.postId),
                ),
                child: Text(context.tr('community_retry')),
              ),
          ],
        ),
      );
    }
    if (loaded == null || loaded.commentsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (loaded.comments.isEmpty) {
      return Center(
        child: Text(
          context.tr('community_comments_empty'),
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    return ListView.separated(
      itemCount: loaded.comments.length,
      separatorBuilder: (_, _) => const Divider(color: Colors.white12),
      itemBuilder: (context, index) {
        final comment = loaded.comments[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${comment.userName} · ${comment.timeAgo == '__TIME_UNAVAILABLE__' ? context.tr('community_time_unavailable') : comment.timeAgo}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 4),
              SelectableText(
                comment.content,
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }
}
