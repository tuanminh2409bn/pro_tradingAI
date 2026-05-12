with open('lib/features/auth/web/login_web_page.dart', 'r') as f:
    content = f.read()

# remove garbage at the end
content = content.replace("}\n}\n),\n    );\n  }\n}", "}\n}")

with open('lib/features/auth/web/login_web_page.dart', 'w') as f:
    f.write(content)
