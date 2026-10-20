import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home.dart';
import 'services/device.dart';
import 'services/stream_health.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Device.detect();
  await StreamHealth.load();
  runApp(const M3UPlayer());
}

class M3UPlayer extends StatelessWidget {
  const M3UPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB0127A),
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF120D1F),
      surfaceContainer: const Color(0xFF1C162C),
      surfaceContainerHighest: const Color(0xFF2A2240),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Live TV',
      // D-pad arrows move focus and OK selects, on every platform.
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const DirectionalFocusIntent(TraversalDirection.left),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const DirectionalFocusIntent(TraversalDirection.right),
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const DirectionalFocusIntent(TraversalDirection.up),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const DirectionalFocusIntent(TraversalDirection.down),
        const SingleActivator(LogicalKeyboardKey.select):
            const ActivateIntent(),
      },
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.surface,
        // Strong focus highlight so the TV remote's position is easy to see.
        focusColor: colorScheme.primary.withValues(alpha: 0.35),
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const Home(),
    );
  }
}
