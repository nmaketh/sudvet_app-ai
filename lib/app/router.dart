import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/utils/go_router_refresh_stream.dart';
import '../features/animals/ui/animal_detail_page.dart';
import '../features/animals/ui/animal_new_page.dart';
import '../features/animals/ui/animals_list_page.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/auth/bloc/auth_state.dart';
import '../features/auth/ui/login_page.dart';
import '../features/auth/ui/forgot_password_page.dart';
import '../features/auth/ui/signup_page.dart';
import '../features/auth/ui/splash_page.dart';
import '../features/auth/ui/verify_signup_page.dart';
import '../features/cases/ui/case_detail_page.dart';
import '../features/cases/ui/case_chat_page.dart';
import '../features/cases/data/case_repository.dart';
import '../features/cases/ui/history_page.dart';
import '../features/cases/ui/new_case_page.dart';
import '../features/cases/ui/result_page.dart';
import '../features/home/ui/home_page.dart';
import '../features/learn/ui/learn_page.dart';
import '../features/settings/ui/settings_page.dart';
import 'app_shell.dart';

const _devServerSettingsEnabled = bool.fromEnvironment(
  'ENABLE_DEV_SERVER_SETTINGS',
  defaultValue: false,
);

GoRouter buildRouter({required AuthBloc authBloc}) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
    redirect: (context, state) {
      final authState = authBloc.state;
      final location = state.matchedLocation;
      final isSplash = location == '/splash';
      final isLegacyWelcome = location == '/welcome';
      final isAuthRoute =
          location == '/login' ||
          location == '/signup' ||
          location == '/forgot-password';
      final isPublicSetupRoute =
          _devServerSettingsEnabled && location == '/setup-api';
      final isOtpRoute = location == '/verify-signup';
      final isPublicRoute =
          isAuthRoute || isPublicSetupRoute || isOtpRoute || isLegacyWelcome;
      final isAuthenticated = authState is AuthAuthenticated;
      final isUnknown =
          authState is AuthUnknown ||
          (authState is AuthAuthenticating && authState.checkingSession);

      if (isUnknown) {
        return isSplash ? null : '/splash';
      }

      if (!isAuthenticated) {
        if (isLegacyWelcome) {
          return '/login';
        }
        return isPublicRoute ? null : '/login';
      }

      if (isAuthenticated &&
          (isAuthRoute || isOtpRoute || isSplash || isLegacyWelcome)) {
        return '/app/home';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GoRoute(
        path: '/welcome',
        redirect: (context, state) => '/login',
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(path: '/signup', builder: (context, state) => const SignUpPage()),
      GoRoute(
        path: '/verify-signup',
        builder: (context, state) {
          final signupToken = state.uri.queryParameters['token'] ?? '';
          final email = state.uri.queryParameters['email'] ?? '';
          if (signupToken.isEmpty || email.isEmpty) {
            return const LoginPage();
          }
          final devOtp = state.uri.queryParameters['dev'];
          return VerifySignupPage(
            signupToken: signupToken,
            email: email,
            devOtp: devOtp?.isNotEmpty == true ? devOtp : null,
          );
        },
      ),
      if (_devServerSettingsEnabled)
        GoRoute(
          path: '/setup-api',
          builder: (context, state) =>
              const SettingsPage(focusConnection: true, publicMode: true),
        ),
      GoRoute(path: '/app', redirect: (context, state) => '/app/home'),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/home',
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/new-case',
                builder: (context, state) {
                  final animalId = state.uri.queryParameters['animalId'];
                  return NewCasePage(preselectedAnimalId: animalId);
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/history',
                builder: (context, state) => const HistoryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/learn',
                builder: (context, state) => const LearnPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/app/animals',
        builder: (context, state) => const AnimalsListPage(),
      ),
      GoRoute(
        path: '/app/animal/new',
        builder: (context, state) {
          final shouldReturnId = state.uri.queryParameters['select'] == '1';
          return AnimalNewPage(returnCreatedId: shouldReturnId);
        },
      ),
      GoRoute(
        path: '/app/case/:id/chat',
        builder: (context, state) {
          final caseId = state.pathParameters['id']!;
          final authState = authBloc.state;
          final serverRole = authState is AuthAuthenticated
              ? authState.user.role.toLowerCase()
              : 'chw';
          // Admin cannot participate in private VET↔CAHW chat.
          if (serverRole == 'admin') {
            return Scaffold(
              appBar: AppBar(title: const Text('Case Chat')),
              body: const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Chat is private between the CAHW and the assigned vet.\nAdmins use the Audit Timeline.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }
          return CaseChatPage(
            caseId: caseId,
            caseRepository: context.read<CaseRepository>(),
            initialUserRole: serverRole,
          );
        },
      ),
      GoRoute(
        path: '/app/case/:id',
        builder: (context, state) {
          final caseId = state.pathParameters['id']!;
          return CaseDetailPage(caseId: caseId);
        },
      ),
      GoRoute(
        path: '/app/result/:id',
        builder: (context, state) {
          final caseId = state.pathParameters['id']!;
          return ResultPage(caseId: caseId);
        },
      ),
      GoRoute(
        path: '/app/animal/:id',
        builder: (context, state) {
          final animalId = state.pathParameters['id']!;
          return AnimalDetailPage(animalId: animalId);
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Page not found: ${state.uri}'),
        ),
      ),
    ),
  );
}
