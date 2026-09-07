import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../../core/constants/colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../data/models/news_models.dart';
import '../../../data/repositories/news_repository.dart';
import '../../../logic/navigation_cubit.dart';
import '../bloc/news_bloc.dart';
import '../bloc/news_event.dart';
import '../bloc/news_state.dart';

class NewsFeedWebPage extends StatefulWidget {
  final String? userId;
  final VoidCallback? onMenuPressed;
  const NewsFeedWebPage({super.key, this.userId, this.onMenuPressed});

  @override
  State<NewsFeedWebPage> createState() => _NewsFeedWebPageState();
}

class _NewsFeedWebPageState extends State<NewsFeedWebPage> {
  final TextEditingController _chatController = TextEditingController();

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          NewsBloc(newsRepository: context.read<NewsRepository>())
            ..add(LoadNewsData(userId: widget.userId)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocBuilder<NewsBloc, NewsState>(
          builder: (context, state) {
            if (state is NewsLoading || state is NewsInitial) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            if (state is NewsError) {
              return Center(
                child: Text(
                  state.message,
                  style: const TextStyle(color: AppColors.bear),
                ),
              );
            }

            if (state is NewsLoaded) {
              return Column(
                children: [
                  _WebTopNavbar(onMenuPressed: widget.onMenuPressed),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isMobile = constraints.maxWidth < 900;
                        if (isMobile) {
                          // Mobile: single scrollable column
                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildHeader(isMobile),
                                const SizedBox(height: 24),
                                _buildSentimentPulse(state.pulse),
                                const SizedBox(height: 24),
                                _buildNewsGrid(state.articles, isMobile),
                                const SizedBox(height: 24),
                                _buildAIChatCard(context, state),
                              ],
                            ),
                          );
                        }
                        // Desktop: left column scrolls, right chat panel is sticky
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // LEFT: Scrollable news content
                            Expanded(
                              flex: 2,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildHeader(isMobile),
                                    const SizedBox(height: 32),
                                    _buildSentimentPulse(state.pulse),
                                    const SizedBox(height: 24),
                                    _buildNewsGrid(state.articles, isMobile),
                                    const SizedBox(height: 32),
                                  ],
                                ),
                              ),
                            ),
                            // RIGHT: Sticky AI chat panel
                            Container(
                              width: 360,
                              padding: const EdgeInsets.fromLTRB(0, 24, 24, 24),
                              child: _buildAIChatCard(context, state),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('news_page_title'),
            style: TextStyle(
              fontSize: isMobile ? 24 : 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('news_page_desc'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: isMobile ? 12 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentimentPulse(SentimentPulse pulse) {
    return Builder(
      builder: (context) {
        String moodText;
        if (pulse.greedPercent > 60) {
          moodText = context.tr('news_bullish');
        } else if (pulse.fearPercent > 60) {
          moodText = context.tr('news_bearish');
        } else if (pulse.greedPercent > pulse.fearPercent) {
          moodText = context.tr('news_neutral_bullish');
        } else {
          moodText = context.tr('news_neutral_bearish');
        }

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.tr('news_sentiment_title'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.white54,
                      letterSpacing: 1,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      pulse.phase,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text(
                    '${pulse.globalScore}',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          moodText,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${context.tr("news_fear")}: ${pulse.fearPercent.toStringAsFixed(1)}% | ${context.tr("news_neutral")}: ${pulse.neutralPercent.toStringAsFixed(1)}% | ${context.tr("news_greed")}: ${pulse.greedPercent.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  _SentimentBar(
                    label: context.tr('news_fear'),
                    value: pulse.fearPercent / 100,
                    color: AppColors.bear,
                  ),
                  const SizedBox(width: 8),
                  _SentimentBar(
                    label: context.tr('news_neutral'),
                    value: pulse.neutralPercent / 100,
                    color: Colors.white24,
                  ),
                  const SizedBox(width: 8),
                  _SentimentBar(
                    label: context.tr('news_greed'),
                    value: pulse.greedPercent / 100,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNewsGrid(List<NewsArticle> articles, bool isMobile) {
    if (articles.isEmpty) {
      return Builder(
        builder: (context) => Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Center(
            child: Text(
              context.tr('news_no_articles'),
              style: const TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile ? 1 : 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        mainAxisExtent: 235,
      ),
      itemCount: articles.length,
      itemBuilder: (context, index) {
        final article = articles[index];
        return _NewsCard(article: article);
      },
    );
  }

  Widget _buildAIChatCard(BuildContext context, NewsLoaded state) {
    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.tr('news_ai_title'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                // Clear history button
                Tooltip(
                  message: context.tr('news_ai_clear_tooltip'),
                  child: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.white30,
                      size: 18,
                    ),
                    onPressed: state.chatMessages.isEmpty
                        ? null
                        : () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppColors.surface,
                                title: Text(
                                  context.tr('news_ai_clear_title'),
                                  style: const TextStyle(color: Colors.white),
                                ),
                                content: Text(
                                  context.tr('news_ai_clear_content'),
                                  style: const TextStyle(color: Colors.white54),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: Text(
                                      context.tr('news_ai_cancel'),
                                      style: const TextStyle(
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      context.read<NewsBloc>().add(
                                        const ClearNewsChatHistory(),
                                      );
                                    },
                                    child: Text(
                                      context.tr('news_ai_delete'),
                                      style: const TextStyle(
                                        color: AppColors.bear,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            ),
          ),
          // ── Loading History Indicator ──
          if (state.isLoadingHistory)
            const LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              color: AppColors.secondary,
              minHeight: 2,
            ),
          // ── Messages ──
          Expanded(
            child: state.chatMessages.isEmpty && !state.isLoadingHistory
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: AppColors.primary.withValues(alpha: 0.3),
                          size: 32,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.tr('news_ai_empty_hint'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.25),
                            fontSize: 14,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.chatMessages.length,
                    itemBuilder: (context, index) {
                      final msg = state.chatMessages[index];
                      final isAi = msg['isAi'] as bool;
                      // Sentinel: __WELCOME__ → always render localized text
                      final rawText = msg['text'] as String;
                      final text = rawText == '__WELCOME__'
                          ? context.tr('news_ai_welcome')
                          : rawText;
                      return _ChatMessage(text: text, isAi: isAi);
                    },
                  ),
          ),
          // ── AI Thinking Indicator ──
          if (state.isAiThinking)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                color: AppColors.primary,
                minHeight: 1,
              ),
            ),
          // ── Input Row ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Builder(
              builder: (innerContext) {
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: context.tr('news_ai_placeholder'),
                          hintStyle: const TextStyle(
                            color: Colors.white24,
                            fontSize: 15,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.03),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (val) {
                          if (val.trim().isNotEmpty) {
                            innerContext.read<NewsBloc>().add(
                              AskAIAnalyst(val),
                            );
                            _chatController.clear();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: () {
                        if (_chatController.text.trim().isNotEmpty) {
                          innerContext.read<NewsBloc>().add(
                            AskAIAnalyst(_chatController.text),
                          );
                          _chatController.clear();
                        }
                      },
                      icon: const Icon(
                        Icons.send,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SentimentBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _SentimentBar({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white38,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: value,
            color: color,
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            minHeight: 4,
          ),
        ],
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  final NewsArticle article;
  const _NewsCard({required this.article});

  static const String _backendUrl = 'https://103-69-189-243.sslip.io';

  /// Route external image URLs through our backend proxy to bypass CORS.
  String _proxyImage(String url) {
    if (url.isEmpty) {
      return 'https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=600&auto=format&fit=crop&q=80';
    }
    // Unsplash already has CORS headers — no need to proxy
    if (url.contains('unsplash.com')) return url;
    final encoded = Uri.encodeComponent(url);
    return '$_backendUrl/api/image-proxy?url=$encoded';
  }

  void _showArticleDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final imageSrc = _proxyImage(article.imageUrl);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 40,
          ),
          child: Container(
            width: 600,
            constraints: const BoxConstraints(maxHeight: 700),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image header with Close button
                  Stack(
                    children: [
                      Image.network(
                        imageSrc,
                        height: 240,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 240,
                            color: Colors.grey.shade900,
                            child: const Center(
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.white24,
                                size: 48,
                              ),
                            ),
                          );
                        },
                      ),
                      // Gradient overlay
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.3),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.8),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Close button
                      Positioned(
                        top: 16,
                        right: 16,
                        child: CircleAvatar(
                          backgroundColor: Colors.black54,
                          radius: 16,
                          child: IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                            onPressed: () => Navigator.pop(context),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      // Meta info tags
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                article.source.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              article.timeAgo,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Detailed body content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            article.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Divider(color: Colors.white10),
                          const SizedBox(height: 16),
                          Text(
                            article.summary.isNotEmpty
                                ? article.summary
                                : 'No description available for this article.',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Footer Actions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF15181b),
                      border: Border(top: BorderSide(color: Colors.white10)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (article.impact.toUpperCase() == 'HIGH') ...[
                          OutlinedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              context.read<NavigationCubit>().getNavBarItem(
                                NavbarItem.tradingRoom,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'HIGH IMPACT — Red Zone will appear on Trading Room chart',
                                  ),
                                  backgroundColor: AppColors.bear,
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.bear,
                              side: const BorderSide(color: AppColors.bear),
                            ),
                            child: const Text(
                              'SHOW RED ZONE',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'CLOSE',
                            style: TextStyle(
                              color: Colors.white54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        if (article.url.isNotEmpty)
                          ElevatedButton.icon(
                            icon: const Icon(
                              Icons.open_in_new,
                              size: 16,
                              color: Colors.black,
                            ),
                            label: const Text(
                              'READ FULL ARTICLE',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () {
                              // Use dart:html window.open() — the only 100% reliable
                              // method to open external URLs on Flutter Web.
                              html.window.open(article.url, '_blank');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageSrc = _proxyImage(article.imageUrl);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showArticleDetail(context),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Article Image
                Image.network(
                  imageSrc,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 140,
                      color: Colors.grey.shade900,
                      child: const Center(
                        child: Icon(
                          Icons.image_not_supported,
                          color: Colors.white12,
                          size: 32,
                        ),
                      ),
                    );
                  },
                ),
                // Article Content
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            article.source,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (article.impact.toUpperCase() == 'HIGH') ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.bear.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'HIGH',
                                style: TextStyle(
                                  color: AppColors.bear,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            article.timeAgo,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white24,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        article.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatMessage extends StatelessWidget {
  final String text;
  final bool isAi;
  const _ChatMessage({required this.text, required this.isAi});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: isAi
                ? AppColors.primary.withValues(alpha: 0.2)
                : Colors.white12,
            child: Icon(
              isAi ? Icons.smart_toy : Icons.person,
              size: 12,
              color: isAi ? AppColors.primary : Colors.white70,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isAi
                    ? Colors.white.withValues(alpha: 0.03)
                    : AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
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
          const SizedBox(width: 40),
          Expanded(
            child: Text(
              context.tr('news_page_title'),
              style: const TextStyle(color: Color(0xFFc3c6d8), fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.rss_feed, color: Color(0xFFc3c6d8), size: 18),
          const SizedBox(width: 16),
          const Icon(Icons.notifications, color: Color(0xFFc3c6d8), size: 18),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () =>
                context.read<AuthBloc>().add(AuthLogoutRequested()),
            icon: const Icon(Icons.logout, color: AppColors.bear, size: 18),
          ),
        ],
      ),
    );
  }
}
