import re

with open('lib/core/localization/app_localizations.dart', 'r') as f:
    content = f.read()

en_updates = """      'trading_room': 'Trading Room',
      'journal': 'Journal',
      'news_feed': 'News Feed',
      'backtest_dojo': 'Backtest Dojo',
      'community': 'Community',
      'market_radar': 'Market Radar',
      'referral_hub': 'Referral Hub',
      'profile': 'Profile',
      'admin_center': 'Admin Center',
"""

vi_updates = """      'trading_room': 'Phòng Giao Dịch',
      'journal': 'Nhật Ký',
      'news_feed': 'Tin Tức Thị Trường',
      'backtest_dojo': 'Sân Luyện Tập',
      'community': 'Cộng Đồng',
      'market_radar': 'Radar Phân Tích',
      'referral_hub': 'Giới Thiệu & Đối Tác',
      'profile': 'Hồ Sơ Của Tôi',
      'admin_center': 'Quản Trị Hệ Thống',
"""

# Find insert positions
en_pos = content.find("    'vi': {")
if en_pos != -1:
    content = content[:en_pos-2] + ",\n" + en_updates + content[en_pos-2:]

vi_pos = content.rfind("    }")
if vi_pos != -1:
    content = content[:vi_pos] + vi_updates + content[vi_pos:]

with open('lib/core/localization/app_localizations.dart', 'w') as f:
    f.write(content)
