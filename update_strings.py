with open('lib/features/auth/web/login_web_page.dart', 'r') as f:
    c = f.read()

# _buildAuthForm strings
c = c.replace("'CREATE ACCOUNT' : 'SYSTEM ACCESS'", "context.tr('create_account') : context.tr('system_access')")
c = c.replace("'Join the next generation of trading'\n              : 'Authorize your session to continue'", "context.tr('register_desc')\n              : context.tr('login_desc')")
c = c.replace("'EMAIL ADDRESS'", "context.tr('email_label')")
c = c.replace("'ACCESS KEY / PASSWORD'", "context.tr('password_label')")
c = c.replace("'CREATE ACCOUNT' : 'SECURE LOGIN'", "context.tr('create_account') : context.tr('secure_login')")
c = c.replace("'OR',", "context.tr('or'),")
c = c.replace("'ALREADY HAVE AN ACCOUNT? LOGIN'\n                  : 'REQUEST ACCESS KEY'", "context.tr('already_have_account')\n                  : context.tr('request_access_key')")

# _buildGoogleBtn
c = c.replace("'CONTINUE WITH GOOGLE'", "context.tr('continue_with_google')")

# _handleAuth
c = c.replace("'Please fill all fields'", "context.tr('fill_all_fields')")

with open('lib/features/auth/web/login_web_page.dart', 'w') as f:
    f.write(c)
