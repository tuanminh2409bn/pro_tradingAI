with open('lib/features/auth/web/login_web_page.dart', 'r') as f:
    content = f.read()

# Add imports
if 'language_toggle.dart' not in content:
    content = content.replace("import '../../../core/localization/app_localizations.dart';", "import '../../../core/localization/app_localizations.dart';\nimport '../../../core/widgets/language_toggle.dart';\nimport '../../../core/localization/locale_cubit.dart';")

# Fix texts in the form
content = content.replace("'CREATE ACCOUNT' : 'SYSTEM ACCESS'", "context.tr('create_account') : context.tr('system_access')")
content = content.replace("'Join the next generation of trading'\n              : 'Authorize your session to continue'", "context.tr('register_desc')\n              : context.tr('login_desc')")
content = content.replace("label: 'EMAIL ADDRESS',", "label: context.tr('email_label'),")
content = content.replace("label: 'ACCESS KEY / PASSWORD',", "label: context.tr('password_label'),")
content = content.replace("'OR',", "context.tr('or'),")
content = content.replace("'ALREADY HAVE AN ACCOUNT? LOGIN'\n                  : 'REQUEST ACCESS KEY'", "context.tr('already_have_account')\n                  : context.tr('request_access_key')")

# Fix button texts
content = content.replace("_isRegistering ? 'CREATE ACCOUNT' : 'SECURE LOGIN'", "_isRegistering ? context.tr('create_account') : context.tr('secure_login')")
content = content.replace("'CONTINUE WITH GOOGLE'", "context.tr('continue_with_google')")
content = content.replace("'Please fill all fields'", "context.tr('fill_all_fields')")

# Fix branding texts
content = content.replace("'Neural-Network Driven Signals'", "context.tr('neural_network_signals')")
content = content.replace("'Zero-Latency Execution'", "context.tr('zero_latency')")
content = content.replace("'Global Liquidity Aggregation'", "context.tr('global_liquidity')")

# Inject Language Toggle into _buildDesktopLayout
target_desktop = """          ),
        ],
      ),
    );
  }"""
replace_desktop = """          ),
        ],
      ),
      Positioned(top: 24, right: 24, child: const LanguageToggle()),
      ],
    );
  }"""
if 'child: const LanguageToggle()' not in content:
    content = content.replace('Widget _buildDesktopLayout() {\n    return SizedBox.expand(', 'Widget _buildDesktopLayout() {\n    return Stack(children: [\nSizedBox.expand(')
    content = content.replace(target_desktop, replace_desktop)
    
    # Inject Language Toggle into _buildMobileLayout
    target_mobile = """  Widget _buildMobileLayout() {
    return Stack(
      children: [
        Positioned.fill("""
    replace_mobile = """  Widget _buildMobileLayout() {
    return Stack(
      children: [
        const Positioned(top: 24, right: 24, child: LanguageToggle()),
        Positioned.fill("""
    content = content.replace(target_mobile, replace_mobile)

with open('lib/features/auth/web/login_web_page.dart', 'w') as f:
    f.write(content)
