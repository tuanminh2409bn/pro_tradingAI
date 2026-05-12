import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'locale_cubit.dart';

class AppLocalizations {
  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'system_access': 'SYSTEM ACCESS',
      'create_account': 'CREATE ACCOUNT',
      'login_desc': 'Authorize your session to continue',
      'register_desc': 'Join the next generation of trading',
      'email_label': 'EMAIL ADDRESS',
      'password_label': 'ACCESS KEY / PASSWORD',
      'secure_login': 'SECURE LOGIN',
      'or': 'OR',
      'continue_with_google': 'CONTINUE WITH GOOGLE',
      'already_have_account': 'ALREADY HAVE AN ACCOUNT? LOGIN',
      'request_access_key': 'REQUEST ACCESS KEY',
      'fill_all_fields': 'Please fill all fields',
      'neural_network_signals': 'Neural-Network Driven Signals',
      'zero_latency': 'Zero-Latency Execution',
      'global_liquidity': 'Global Liquidity Aggregation',
      'execution_engine': 'EXECUTION ENGINE',
      'lot_size': 'LOT SIZE',
      'sell': 'SELL',
      'buy': 'BUY',
      'analyze_data': 'ANALYZE DATA (AI)',
      'active_signals': 'ACTIVE SIGNALS',
      'no_signals': 'No signals yet. Press Analyze AI.',
      'equity': 'Equity',
      'link_api': 'LINK BROKER API',
      'link_broker_title': 'Link MT4/MT5 Account',
      'link_broker_desc':
          'The system only requires Read-only password to sync. Absolutely safe, the system CANNOT trade or withdraw your money.',
      'account_number': 'Account Number (Login)',
      'investor_password': 'Password (Investor Password)',
      'broker_server': 'Broker Server (e.g. Exness-Real)',
      'cancel': 'Cancel',
      'link_now': 'Link Now',
      'sending_link_request': 'Sending link request to Server...',
      'analyzing_request': 'Sending AI analysis request...',
      'trading_room': 'Trading Room',
      'journal': 'Journal',
      'news_feed': 'News Feed',
      'backtest_dojo': 'Backtest Dojo',
      'community': 'Community',
      'market_radar': 'Market Radar',
      'referral_hub': 'Referral Hub',
      'profile': 'Profile',
      'admin_center': 'Admin Center',
      'xauusd_label': 'XAUUSD (Gold)',
      'eurusd_label': 'EURUSD (Forex)',
      'btcusd_label': 'BTCUSD (Crypto)',
      'loading': 'Loading...',
      'order_executed': '{type} Order Executed: {lot} Lots',
    },
    'vi': {
      'system_access': 'ĐĂNG NHẬP HỆ THỐNG',
      'create_account': 'TẠO TÀI KHOẢN',
      'login_desc': 'Xác thực phiên của bạn để tiếp tục',
      'register_desc': 'Tham gia thế hệ giao dịch mới',
      'email_label': 'ĐỊA CHỈ EMAIL',
      'password_label': 'MẬT KHẨU / KHÓA TRUY CẬP',
      'secure_login': 'ĐĂNG NHẬP BẢO MẬT',
      'or': 'HOẶC',
      'continue_with_google': 'TIẾP TỤC VỚI GOOGLE',
      'already_have_account': 'ĐÃ CÓ TÀI KHOẢN? ĐĂNG NHẬP',
      'request_access_key': 'YÊU CẦU KHÓA TRUY CẬP',
      'fill_all_fields': 'Vui lòng điền đủ thông tin',
      'neural_network_signals': 'Tín hiệu phân tích bằng mạng nơ-ron',
      'zero_latency': 'Khớp lệnh không độ trễ',
      'global_liquidity': 'Tổng hợp thanh khoản toàn cầu',
      'execution_engine': 'ĐỘNG CƠ KHỚP LỆNH',
      'lot_size': 'KHỐI LƯỢNG (LOT)',
      'sell': 'BÁN',
      'buy': 'MUA',
      'analyze_data': 'PHÂN TÍCH DỮ LIỆU (AI)',
      'active_signals': 'TÍN HIỆU ĐANG HOẠT ĐỘNG',
      'no_signals': 'Chưa có tín hiệu. Nhấn Phân tích AI.',
      'equity': 'Vốn',
      'link_api': 'LIÊN KẾT API SÀN',
      'link_broker_title': 'Liên kết tài khoản MT4/MT5',
      'link_broker_desc':
          'Hệ thống chỉ yêu cầu Mật khẩu chỉ đọc (Read-only password) để đồng bộ. Tuyệt đối an toàn, hệ thống KHÔNG THỂ vào lệnh hoặc rút tiền của bạn.',
      'account_number': 'Số tài khoản (Login)',
      'investor_password': 'Mật khẩu (Investor Password)',
      'broker_server': 'Server Sàn (VD: Exness-Real)',
      'cancel': 'Hủy',
      'link_now': 'Liên Kết Ngay',
      'sending_link_request': 'Đang gửi yêu cầu liên kết đến Server...',
      'analyzing_request': 'Đã gửi yêu cầu phân tích dữ liệu AI...',
      'trading_room': 'Phòng Giao Dịch',
      'journal': 'Nhật Ký',
      'news_feed': 'Tin Tức Thị Trường',
      'backtest_dojo': 'Sân Luyện Tập',
      'community': 'Cộng Đồng',
      'market_radar': 'Radar Phân Tích',
      'referral_hub': 'Giới Thiệu & Đối Tác',
      'profile': 'Hồ Sơ Của Tôi',
      'admin_center': 'Quản Trị Hệ Thống',
      'xauusd_label': 'XAUUSD (Vàng)',
      'eurusd_label': 'EURUSD (Forex)',
      'btcusd_label': 'BTCUSD (Crypto)',
      'loading': 'Đang tải...',
      'order_executed': 'Khớp lệnh {type}: {lot} Lot',
    },
  };

  static String get(String langCode, String key) {
    return _localizedValues[langCode]?[key] ?? key;
  }
}

extension LocalizationExtension on BuildContext {
  String tr(String key) {
    final langCode = watch<LocaleCubit>().state;
    return AppLocalizations.get(langCode, key);
  }
}
