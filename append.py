with open('lib/features/auth/web/login_web_page.dart', 'a') as f:
    f.write("""

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
              child: Text('EN', style: TextStyle(color: lang == 'en' ? AppColors.primary : Colors.white54, fontWeight: FontWeight.bold)),
            ),
            const Text('|', style: TextStyle(color: Colors.white24)),
            TextButton(
              onPressed: () => context.read<LocaleCubit>().setLanguage('vi'),
              child: Text('VI', style: TextStyle(color: lang == 'vi' ? AppColors.primary : Colors.white54, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}
""")
