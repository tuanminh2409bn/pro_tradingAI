with open('lib/features/trading_room/web/trading_room_web_page.dart', 'r') as f:
    content = f.read()

# remove garbage at the end
clean_end = """
      },
    );
  }
}"""
idx = content.rfind(clean_end)
if idx != -1:
    content = content[:idx + len(clean_end)] + '\n'

with open('lib/features/trading_room/web/trading_room_web_page.dart', 'w') as f:
    f.write(content)
