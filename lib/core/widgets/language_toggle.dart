import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../constants/colors.dart';
import '../localization/locale_cubit.dart';

class LanguageToggle extends StatelessWidget {
  final bool isCollapsed;
  const LanguageToggle({super.key, this.isCollapsed = false});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LocaleCubit, String>(
      builder: (context, lang) {
        if (isCollapsed) {
          return InkWell(
            onTap: () => context.read<LocaleCubit>().setLanguage(lang == 'en' ? 'vi' : 'en'),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                lang.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          );
        }
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
