with open('lib/features/auth/web/login_web_page.dart', 'r') as f:
    lines = f.readlines()

for i in range(len(lines)):
    line = lines[i]
    if "const SnackBar(" in line and "context.tr" in line:
        lines[i] = line.replace("const SnackBar(", "SnackBar(")
    if "const Column(" in line and "context.tr" in "".join(lines[i:i+20]):
        lines[i] = line.replace("const Column(", "Column(")
    if "const Padding(" in line and "context.tr" in "".join(lines[i:i+20]):
        lines[i] = line.replace("const Padding(", "Padding(")

with open('lib/features/auth/web/login_web_page.dart', 'w') as f:
    f.writelines(lines)
