import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import 'dart:ui';
import '../../../core/constants/colors.dart';
import '../../../data/models/community_models.dart';
import '../../../data/repositories/community_repository.dart';
import '../bloc/community_bloc.dart';
import '../bloc/community_event.dart';
import '../bloc/community_state.dart';

class CommunityWebPage extends StatefulWidget {
  const CommunityWebPage({super.key});

  @override
  State<CommunityWebPage> createState() => _CommunityWebPageState();
}

class _CommunityWebPageState extends State<CommunityWebPage> {
  final TextEditingController _postController = TextEditingController();

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
        body: BlocBuilder<CommunityBloc, CommunityState>(
          builder: (context, state) {
            if (state is CommunityLoading || state is CommunityInitial) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }

            if (state is CommunityError) {
              return Center(child: Text(state.message, style: const TextStyle(color: AppColors.bear)));
            }

            if (state is CommunityLoaded) {
              return Column(
                children: [
                  const _WebTopNavbar(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Community Feed
                              Expanded(
                                flex: 2,
                                child: Column(
                                  children: [
                                    _buildPostCreationArea(context),
                                    const SizedBox(height: 32),
                                    _buildFeedList(state.posts),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 40),
                              // Right Side Panels
                              SizedBox(
                                width: 320,
                                child: Column(
                                  children: [
                                    _LeaderboardCard(entries: state.leaderboard),
                                    const SizedBox(height: 32),
                                    const _AchievementsCard(),
                                    const SizedBox(height: 32),
                                    const _TrendingSignalsCard(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const _WebTickerFooter(),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildPostCreationArea(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withOpacity(0.2))), child: const Icon(Icons.person, color: Colors.white24)),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _postController,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Share your setup from the Trading Room...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    fillColor: const Color(0xFF0b0e11),
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _buildPostToolBtn(Icons.insert_chart, 'Setup'),
                  const SizedBox(width: 8),
                  _buildPostToolBtn(Icons.image, 'Chart'),
                ],
              ),
              ElevatedButton(
                onPressed: () {
                  if (_postController.text.isNotEmpty) {
                    context.read<CommunityBloc>().add(CreatePost(_postController.text));
                    _postController.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Analysis posted successfully!'), backgroundColor: AppColors.primary),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Post Analysis', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPostToolBtn(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white54),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildFeedList(List<CommunityPost> posts) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: posts.length,
      itemBuilder: (context, index) => _PostCard(post: posts[index]),
    );
  }
}

class _PostCard extends StatelessWidget {
  final CommunityPost post;
  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface, 
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
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
                        Container(width: 40, height: 40, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white10), child: const Icon(Icons.person, size: 20, color: Colors.white24)),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(post.userName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                if (post.isVerified) const Padding(padding: EdgeInsets.only(left: 4.0), child: Icon(Icons.verified, size: 14, color: AppColors.primary)),
                              ],
                            ),
                            Text('${post.timeAgo.toUpperCase()} • ${post.tradeInfo}', style: TextStyle(fontSize: 8, color: post.isProfit ? AppColors.primary : AppColors.bear, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                          ],
                        ),
                      ],
                    ),
                    _buildProfitBlur(post.profit, post.isProfit),
                  ],
                ),
                const SizedBox(height: 16),
                Text(post.content, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                const SizedBox(height: 16),
                Container(
                  height: 300, width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black, 
                    borderRadius: BorderRadius.circular(8),
                    image: post.chartImageUrl != null ? DecorationImage(image: NetworkImage(post.chartImageUrl!), fit: BoxFit.cover) : null,
                  ),
                  child: post.chartImageUrl == null ? Center(child: Icon(Icons.show_chart, color: post.isProfit ? AppColors.primary.withOpacity(0.1) : AppColors.bear.withOpacity(0.1), size: 64)) : null,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            color: Colors.white.withOpacity(0.02),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _buildActionBtn(Icons.thumb_up, '${post.likes}'),
                    const SizedBox(width: 24),
                    _buildActionBtn(Icons.forum, '${post.comments}'),
                    const SizedBox(width: 24),
                    _buildActionBtn(Icons.share, ''),
                  ],
                ),
                const Row(children: [CircleAvatar(radius: 10, backgroundColor: Colors.white10), SizedBox(width: -8), CircleAvatar(radius: 10, backgroundColor: Colors.white24)]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitBlur(double value, bool isPositive) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Text(
                '${isPositive ? '+' : ''}\$${value.abs().toStringAsFixed(2)}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isPositive ? AppColors.primary : AppColors.bear),
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
        const Text('PROFIT (BLURRED)', style: TextStyle(fontSize: 8, color: Colors.white24, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildActionBtn(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.white38),
        if (label.isNotEmpty) const SizedBox(width: 6),
        if (label.isNotEmpty) Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _LeaderboardCard extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  const _LeaderboardCard({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: Column(
        children: [
          const Padding(padding: EdgeInsets.all(20), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('LEADERBOARD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white)), Text('TOP RANKINGS', style: TextStyle(fontSize: 8, color: AppColors.primary, fontWeight: FontWeight.bold))])),
          ...entries.map((entry) => _buildLeaderRow(entry.rank, entry.name, '+${entry.performance}%', entry.volume, entry.rank == 1)),
          Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: TextButton(onPressed: () {}, child: const Text('VIEW ALL RANKINGS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.primary))))),
        ],
      ),
    );
  }
  Widget _buildLeaderRow(int rank, String name, String perf, String vol, bool isFirst) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.02))),
      ),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text('$rank', style: TextStyle(fontWeight: FontWeight.w900, color: isFirst ? AppColors.primary : Colors.white24))),
          Container(width: 32, height: 32, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.white10), child: const Icon(Icons.person, size: 16, color: Colors.white10)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)), Text('VOL: $vol', style: const TextStyle(fontSize: 8, color: Colors.white38))])),
          Text(perf, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.primary)),
        ],
      ),
    );
  }
}

class _AchievementsCard extends StatelessWidget {
  const _AchievementsCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ACHIEVEMENTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildBadge(Icons.workspace_premium, AppColors.primary),
              _buildBadge(Icons.military_tech, const Color(0xFFFFD700)),
              _buildBadge(Icons.auto_awesome, AppColors.secondary),
              _buildBadge(Icons.lock, Colors.white10),
            ],
          ),
        ],
      ),
    );
  }
  Widget _buildBadge(IconData icon, Color color) {
    return Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 24));
  }
}

class _TrendingSignalsCard extends StatelessWidget {
  const _TrendingSignalsCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TRENDING SIGNALS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54)),
          SizedBox(height: 16),
          _TrendRow(tag: '#GoldBullRun', status: 'High Vol', color: AppColors.primary),
          _TrendRow(tag: '#FedMeeting', status: 'Risk On', color: AppColors.bear),
          _TrendRow(tag: '#CryptoHalving', status: 'Trending', color: AppColors.secondary),
        ],
      ),
    );
  }
}

class _TrendRow extends StatelessWidget {
  final String tag;
  final String status;
  final Color color;
  const _TrendRow({required this.tag, required this.status, required this.color});
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(tag, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)), Text(status.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: color))]));
  }
}

class _WebTopNavbar extends StatelessWidget {
  const _WebTopNavbar();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(color: Color(0xFF111417), border: Border(bottom: BorderSide(color: Colors.white10))),
      child: Row(
        children: [
          const Text('KINETIC', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -1, color: Colors.white)),
          const SizedBox(width: 40),
          const Text('Equity: \$42,050.00', style: TextStyle(color: Color(0xFFc3c6d8), fontSize: 13)),
          const Spacer(),
          const Icon(Icons.rss_feed, color: Color(0xFFc3c6d8)),
          const SizedBox(width: 16),
          const Icon(Icons.notifications, color: Color(0xFFc3c6d8)),
          const SizedBox(width: 16),
          IconButton(
            onPressed: () => context.read<AuthBloc>().add(AuthLogoutRequested()),
            icon: const Icon(Icons.logout, color: AppColors.bear, size: 20),
          ),
        ],
      ),
    );
  }
}

class _WebTickerFooter extends StatelessWidget {
  const _WebTickerFooter();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      color: const Color(0xFF0b0e11),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TickerItem('XAUUSD: 2042.12', AppColors.primary),
          SizedBox(width: 32),
          _TickerItem('BTCUSD: 64210.50', AppColors.bear),
          SizedBox(width: 32),
          _TickerItem('EURUSD: 1.0821', Colors.white54),
        ],
      ),
    );
  }
}

class _TickerItem extends StatelessWidget {
  final String text;
  final Color color;
  const _TickerItem(this.text, this.color);
  @override
  Widget build(BuildContext context) {
    return Row(children: [Icon(Icons.trending_up, color: color, size: 14), const SizedBox(width: 4), Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold))]);
  }
}
