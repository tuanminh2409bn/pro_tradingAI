import 'package:flutter_bloc/flutter_bloc.dart';

class LocaleCubit extends Cubit<String> {
  LocaleCubit() : super('en'); // Default to English

  void toggleLanguage() {
    emit(state == 'en' ? 'vi' : 'en');
  }

  void setLanguage(String langCode) {
    if (langCode == 'en' || langCode == 'vi') {
      emit(langCode);
    }
  }
}
