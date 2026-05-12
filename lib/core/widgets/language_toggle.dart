import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../constants/colors.dart';
import '../localization/locale_cubit.dart';

class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LocaleCubit, String>(
      builder: (context, lang) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => context.read<LocaleCubit>().setLanguage('en'),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              ),
              child: Text('EN', style: TextStyle(color: lang == 'en' ? AppColors.primary : Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            const Text('|', style: TextStyle(color: Colors.white24, fontSize: 12)),
            TextButton(
              onPressed: () => context.read<LocaleCubit>().setLanguage('vi'),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              ),
              child: Text('VI', style: TextStyle(color: lang == 'vi' ? AppColors.primary : Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        );
      },
    );
  }
}
