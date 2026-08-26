import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pestify_flutter/core/router/app_router.dart';
import 'package:pestify_flutter/core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: PestifyApp()));
}

class PestifyApp extends ConsumerWidget {
  const PestifyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the router provider so the widget rebuilds if the provider is ever
    // recreated (e.g. during hot restart in development). The GoRouter itself
    // handles auth-driven redirects internally via its refreshListenable.
    final GoRouter router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Pestify',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
