import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/core/localization/locale_cubit.dart';
import 'package:protrading_ai/features/community/web/widgets/community_like_button.dart';

void main() {
  testWidgets('like action fires once and then disables for a liked post', (
    tester,
  ) async {
    var calls = 0;
    Future<void> show({required bool liked, bool busy = false}) =>
        tester.pumpWidget(
          BlocProvider(
            create: (_) => LocaleCubit(),
            child: MaterialApp(
              home: Scaffold(
                body: CommunityLikeButton(
                  postId: 'post123',
                  count: liked ? 8 : 7,
                  liked: liked,
                  busy: busy,
                  onLike: () => calls++,
                ),
              ),
            ),
          ),
        );

    await show(liked: false);
    await tester.tap(find.byKey(const ValueKey('community-like-post123')));
    expect(calls, 1);

    await show(liked: false, busy: true);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );

    await show(liked: true);
    expect(find.textContaining('Liked · 8'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
  });
}
