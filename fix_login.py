with open('lib/features/auth/web/login_web_page.dart', 'r') as f:
    content = f.read()

# remove garbage at the end
clean_end = """
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 20),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
"""
idx = content.find(clean_end)
if idx != -1:
    content = content[:idx + len(clean_end)]

with open('lib/features/auth/web/login_web_page.dart', 'w') as f:
    f.write(content)
