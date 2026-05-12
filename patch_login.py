import re

with open('lib/features/auth/web/login_web_page.dart', 'r') as f:
    content = f.read()

# Add imports if missing
if 'core/localization/app_localizations.dart' not in content:
    content = content.replace("import '../bloc/auth_bloc.dart';", "import '../../../core/localization/app_localizations.dart';\nimport '../../../core/localization/locale_cubit.dart';\nimport '../bloc/auth_bloc.dart';")

content = content.replace("'CREATE ACCOUNT' : 'SYSTEM ACCESS'", "context.tr('create_account') : context.tr('system_access')")
content = content.replace("'Join the next generation of trading'\n              : 'Authorize your session to continue'", "context.tr('register_desc')\n              : context.tr('login_desc')")
content = content.replace("label: 'EMAIL ADDRESS',", "label: context.tr('email_label'),")
content = content.replace("label: 'ACCESS KEY / PASSWORD',", "label: context.tr('password_label'),")
content = content.replace("const Row(\n          children: [", "Row(\n          children: [")
content = content.replace("Expanded(child: Divider(color: Colors.white10)),", "const Expanded(child: Divider(color: Colors.white10)),")
content = content.replace("'OR',", "context.tr('or'),")
content = content.replace("'ALREADY HAVE AN ACCOUNT? LOGIN'\n                  : 'REQUEST ACCESS KEY'", "context.tr('already_have_account')\n                  : context.tr('request_access_key')")

# For _buildMainAuthBtn
content = content.replace("_isRegistering ? 'CREATE ACCOUNT' : 'SECURE LOGIN'", "_isRegistering ? context.tr('create_account') : context.tr('secure_login')")
# For google btn
content = content.replace("'CONTINUE WITH GOOGLE'", "context.tr('continue_with_google')")
content = content.replace("'Please fill all fields'", "context.tr('fill_all_fields')")

# For Neural Network text in branding
content = content.replace("'Neural-Network Driven Signals'", "context.tr('neural_network_signals')")
content = content.replace("'Zero-Latency Execution'", "context.tr('zero_latency')")
content = content.replace("'Global Liquidity Aggregation'", "context.tr('global_liquidity')")

# We want a language switch button. We can put it in the top right of _buildDesktopLayout and _buildMobileLayout.
# Let's add it via Python
if 'LanguageToggle()' not in content:
    content = content.replace('Widget _buildDesktopLayout() {\n    return SizedBox.expand(', "Widget _buildDesktopLayout() {\n    return Stack(children: [ SizedBox.expand(")
    content = content.replace('          ),\n        ],\n      ),\n    );', '          ),\n        ],\n      ), Positioned(top: 24, right: 24, child: const LanguageToggle()), ],\n    );')
    content = content.replace('Widget _buildMobileLayout() {\n    return Stack(\n      children: [', 'Widget _buildMobileLayout() {\n    return Stack(\n      children: [\n        Positioned(top: 24, right: 24, child: const LanguageToggle()),')
    
    # Add LanguageToggle class
    toggle_class = """
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
"""
    content += toggle_class

with open('lib/features/auth/web/login_web_page.dart', 'w') as f:
    f.write(content)
