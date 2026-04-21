import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../../core/constants/colors.dart';
import '../../../data/models/news_models.dart';
import '../../../data/repositories/news_repository.dart';
import '../bloc/news_bloc.dart';
import '../bloc/news_event.dart';
import '../bloc/news_state.dart';
import 'dart:math' as math;

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
      create: (context) => NewsBloc(
        newsRepository: context.read<NewsRepository>(),
      )..add(LoadNewsData(userId: widget.userId)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocBuilder<NewsBloc, NewsState>(
          builder: (context, state) {
            if (state is NewsLoading || state is NewsInitial) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }
            
            if (state is NewsError) {
              return Center(child: Text(state.message, style: const TextStyle(color: AppColors.bear)));
            }

            if (state is NewsLoaded) {
              return Column(
                children: [
                  _WebTopNavbar(onMenuPressed: widget.onMenuPressed),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isMobile = constraints.maxWidth < 900;
                        return SingleChildScrollView(
                          padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(isMobile),
                              const SizedBox(height: 32),
                              if (isMobile) ...[
                                _buildSentimentPulse(state.pulse),
                                const SizedBox(height: 24),
                                _buildNewsGrid(state.articles, isMobile),
                                const SizedBox(height: 24),
                                _buildAIChatCard(state),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        children: [
                                          _buildSentimentPulse(state.pulse),
                                          const SizedBox(height: 24),
                                          _buildNewsGrid(state.articles, isMobile),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(
                                      flex: 1,
                                      child: _buildAIChatCard(state),
                                    ),
                                  ],
                                ),
                            ],
                          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Market Intelligence',
          style: TextStyle(fontSize: isMobile ? 24 : 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
        ),
        const SizedBox(height: 4),
        Text(
          'Real-time news sentiment and DeepSeek AI analysis.',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: isMobile ? 12 : 14),
        ),
      ],
    );
  }

  Widget _buildSentimentPulse(SentimentPulse pulse) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('GLOBAL SENTIMENT PULSE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54, letterSpacing: 1)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(pulse.phase, style: const TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('${pulse.globalScore}', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MARKET MOOD: NEUTRAL-BULLISH', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('Sentiment has improved by 14% over the last 24h as BTC holds support.', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _SentimentBar(label: 'FEAR', value: pulse.fearPercent / 100, color: AppColors.bear),
              const SizedBox(width: 8),
              _SentimentBar(label: 'NEUTRAL', value: pulse.neutralPercent / 100, color: Colors.white24),
              const SizedBox(width: 8),
              _SentimentBar(label: 'GREED', value: pulse.greedPercent / 100, color: AppColors.primary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNewsGrid(List<NewsArticle> articles, bool isMobile) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile ? 1 : 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        mainAxisExtent: 110,
      ),
      itemCount: articles.length,
      itemBuilder: (context, index) {
        final article = articles[index];
        return _NewsCard(article: article);
      },
    );
  }

  Widget _buildAIChatCard(NewsLoaded state) {
    return Container(
      height: 600,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome, color: AppColors.primary, size: 18),
                SizedBox(width: 12),
                Text('DEEPSEEK V3.2 ANALYST', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.chatMessages.length,
              itemBuilder: (context, index) {
                final msg = state.chatMessages[index];
                final isAi = msg['isAi'] as bool;
                return _ChatMessage(text: msg['text'], isAi: isAi);
              },
            ),
          ),
          if (state.isAiThinking)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: AppColors.primary, minHeight: 1),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Ask about market sentiment...',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.03),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        context.read<NewsBloc>().add(AskAIAnalyst(val));
                        _chatController.clear();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () {
                    if (_chatController.text.trim().isNotEmpty) {
                      context.read<NewsBloc>().add(AskAIAnalyst(_chatController.text));
                      _chatController.clear();
                    }
                  },
                  icon: const Icon(Icons.send, color: AppColors.primary, size: 20),
                ),
              ],
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
  const _SentimentBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 8, color: Colors.white38, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: value, color: color, backgroundColor: Colors.white.withOpacity(0.05), minHeight: 4),
        ],
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  final NewsArticle article;
  const _NewsCard({required this.article});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.03)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Text(article.source, style: const TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(article.timeAgo, style: const TextStyle(fontSize: 9, color: Colors.white24)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            article.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
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
            backgroundColor: isAi ? AppColors.primary.withOpacity(0.2) : Colors.white12,
            child: Icon(isAi ? Icons.smart_toy : Icons.person, size: 12, color: isAi ? AppColors.primary : Colors.white70),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isAi ? Colors.white.withOpacity(0.03) : AppColors.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                text,
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12, height: 1.5),
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
      decoration: const BoxDecoration(color: Color(0xFF111417), border: Border(bottom: BorderSide(color: Colors.white10))),
      child: Row(
        children: [
          if (onMenuPressed != null)
            IconButton(
              onPressed: onMenuPressed,
              icon: const Icon(Icons.menu, color: Colors.white, size: 20),
            ),
          const Text('KINETIC', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -1, color: Colors.white)),
          const SizedBox(width: 40),
          const Expanded(child: Text('Equity: \$42,050.00', style: TextStyle(color: Color(0xFFc3c6d8), fontSize: 13), overflow: TextOverflow.ellipsis)),
          const Icon(Icons.rss_feed, color: Color(0xFFc3c6d8), size: 18),
          const SizedBox(width: 16),
          const Icon(Icons.notifications, color: Color(0xFFc3c6d8), size: 18),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => context.read<AuthBloc>().add(AuthLogoutRequested()),
            icon: const Icon(Icons.logout, color: AppColors.bear, size: 18),
          ),
        ],
      ),
    );
  }
}
