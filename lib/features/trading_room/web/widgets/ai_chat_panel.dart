import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../data/models/trading_models.dart';
import '../../bloc/trading_room_bloc.dart';
import '../../bloc/trading_room_event.dart';
import '../../bloc/trading_room_state.dart';

class AIChatPanel extends StatefulWidget {
  const AIChatPanel({super.key});

  @override
  State<AIChatPanel> createState() => _AIChatPanelState();
}

class _AIChatPanelState extends State<AIChatPanel>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  late AnimationController _diamondController;
  bool _isComposing = false;

  @override
  void initState() {
    super.initState();
    _diamondController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _diamondController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    context.read<TradingRoomBloc>().add(SendAIMessage(text));
    _textController.clear();
    setState(() => _isComposing = false);
    _focusNode.requestFocus();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TradingRoomBloc, TradingRoomState>(
      listenWhen: (prev, curr) {
        if (prev is TradingRoomLoaded && curr is TradingRoomLoaded) {
          return prev.chatMessages.length != curr.chatMessages.length;
        }
        return false;
      },
      listener: (context, state) {
        _scrollToBottom();
      },
      builder: (context, state) {
        final messages = state is TradingRoomLoaded
            ? state.chatMessages
            : <ChatMessage>[];
        final isLoading = state is TradingRoomLoaded && state.isAIChatLoading;
        final isLoadingHistory =
            state is TradingRoomLoaded && state.isLoadingHistory;

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.9),
            border: Border(
              left: BorderSide(
                color: AppColors.secondary.withValues(alpha: 0.15),
              ),
            ),
          ),
          child: Column(
            children: [
              _buildHeader(context),
              if (isLoadingHistory)
                const LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  color: AppColors.secondary,
                  minHeight: 2,
                ),
              Expanded(child: _buildMessageList(messages, isLoading)),
              _buildInput(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(
            color: AppColors.secondary.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Row(
        children: [
          // Animated diamond icon
          AnimatedBuilder(
            animation: _diamondController,
            builder: (context, child) {
              return Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.secondary.withValues(
                        alpha: 0.3 + _diamondController.value * 0.5,
                      ),
                      AppColors.secondary.withValues(alpha: 0.1),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.secondary.withValues(
                        alpha: 0.2 + _diamondController.value * 0.3,
                      ),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    '◆',
                    style: TextStyle(color: AppColors.secondary, fontSize: 12),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr('ai_title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr('ai_active'),
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // Clear history button
          Tooltip(
            message: 'Xóa lịch sử chat',
            child: BlocBuilder<TradingRoomBloc, TradingRoomState>(
              builder: (context, state) {
                final hasMessages =
                    state is TradingRoomLoaded && state.chatMessages.isNotEmpty;
                return IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  color: hasMessages ? Colors.white30 : Colors.white12,
                  onPressed: hasMessages
                      ? () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppColors.surface,
                              title: const Text(
                                'Xóa lịch sử?',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              content: const Text(
                                'Tất cả lịch sử chat sẽ bị xóa vĩnh viễn.',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 14,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text(
                                    'Hủy',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    context.read<TradingRoomBloc>().add(
                                      const ClearChatHistory(),
                                    );
                                  },
                                  child: const Text(
                                    'Xóa',
                                    style: TextStyle(color: Color(0xFFff4444)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                      : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.5),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(List<ChatMessage> messages, bool isLoading) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome,
              color: AppColors.secondary.withValues(alpha: 0.3),
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('ai_empty_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: messages.length + (isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length && isLoading) {
          return _buildTypingIndicator();
        }
        return _buildMessageBubble(messages[index]);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;
    final isFallback = message.isFallback && !isUser;
    final bgColor = isUser
        ? AppColors.entry.withValues(alpha: 0.2)
        : isFallback
        ? AppColors.accent.withValues(alpha: 0.12)
        : AppColors.secondary.withValues(alpha: 0.15);
    final borderColor = isUser
        ? AppColors.entry.withValues(alpha: 0.4)
        : isFallback
        ? AppColors.accent.withValues(alpha: 0.45)
        : AppColors.secondary.withValues(alpha: 0.3);
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final timeStr =
        '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (isFallback)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'FALLBACK MODE',
                style: TextStyle(
                  color: AppColors.accent.withValues(alpha: 0.9),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isUser ? 12 : 2),
                bottomRight: Radius.circular(isUser ? 2 : 12),
              ),
              border: Border.all(color: borderColor, width: 0.5),
            ),
            child: Text(
              message.content,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            timeStr,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.2),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.secondary.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.3, end: 1.0),
                  duration: Duration(milliseconds: 400 + i * 200),
                  builder: (context, value, child) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Opacity(
                        opacity: value,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.secondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isComposing
                      ? AppColors.secondary.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: context.tr('ai_placeholder'),
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                onChanged: (text) {
                  setState(() => _isComposing = text.trim().isNotEmpty);
                },
                onSubmitted: (_) => _handleSend(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _isComposing ? _handleSend : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _isComposing
                      ? AppColors.secondary.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isComposing
                        ? AppColors.secondary.withValues(alpha: 0.5)
                        : Colors.transparent,
                  ),
                  boxShadow: _isComposing
                      ? [
                          BoxShadow(
                            color: AppColors.secondary.withValues(alpha: 0.2),
                            blurRadius: 8,
                          ),
                        ]
                      : [],
                ),
                child: Icon(
                  Icons.send_rounded,
                  color: _isComposing
                      ? AppColors.secondary
                      : Colors.white.withValues(alpha: 0.2),
                  size: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
