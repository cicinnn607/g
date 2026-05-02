import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_style.dart';
import 'pages/analysis_page.dart';
import 'pages/diet_page.dart';
import 'pages/exercise_page.dart';
import 'pages/glucose_page.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'provider/health_provider.dart';
import 'services/reminder_service.dart';
import 'services/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  await ReminderService.instance.initialize();
  final isLoggedIn = SupabaseConfig.tryClient()?.auth.currentSession != null;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => HealthProvider()..loadDashboardData(),
        ),
      ],
      child: GlucoseAssistantApp(
        isLoggedIn: isLoggedIn,
        supabaseConfigured: SupabaseConfig.isConfigured,
      ),
    ),
  );
}

class GlucoseAssistantApp extends StatelessWidget {
  final bool isLoggedIn;
  final bool supabaseConfigured;
  const GlucoseAssistantApp({
    super.key,
    required this.isLoggedIn,
    this.supabaseConfigured = true,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '稳啦',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          surface: AppColors.surface,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.text,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 68,
          backgroundColor: Colors.white,
          indicatorColor: AppColors.primary.withValues(alpha: 0.12),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? AppColors.primaryDark
                  : AppColors.muted,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? AppColors.primary
                  : AppColors.muted,
            ),
          ),
        ),
      ),
      home: isLoggedIn
          ? const MainTabScreen()
          : LoginPage(supabaseConfigured: supabaseConfigured),
    );
  }
}

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          HomePage(),
          GlucoseRecordPage(),
          DietRecordPage(),
          ExerciseRecordPage(),
          DataAnalysisPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.water_drop_outlined),
            selectedIcon: Icon(Icons.water_drop),
            label: '血糖',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: '饮食',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_run_outlined),
            selectedIcon: Icon(Icons.directions_run),
            label: '运动',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: '分析',
          ),
        ],
      ),
    );
  }
}
