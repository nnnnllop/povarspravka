import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/widgets/calc_error_banner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // STATE-01 (LEAD-02): красный экран с raw stack trace недопустим в
  // продуктовом приложении — любое непредвиденное исключение рендера
  // показывает понятную панель с сохранением доступа к рецептам.
  ErrorWidget.builder = (details) => const FriendlyErrorPane();
  runApp(
    const ProviderScope(
      child: PovarSpravkaApp(),
    ),
  );
}

class PovarSpravkaApp extends StatelessWidget {
  const PovarSpravkaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Поварская справка',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ru', 'RU'),
        Locale('en', 'US'),
      ],
      locale: const Locale('ru', 'RU'),
      home: const HomeScreen(),
    );
  }
}
