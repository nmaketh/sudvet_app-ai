import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../data/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required AuthRepository authRepository})
    : _authRepository = authRepository,
      super(const AuthUnknown()) {
    on<AuthSessionCheckRequested>(_onSessionCheckRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthGoogleRequested>(_onGoogleRequested);
    on<AuthSignupRequested>(_onSignupRequested);
    on<AuthSignupOtpVerificationRequested>(_onSignupOtpVerificationRequested);
    on<AuthSignupOtpResendRequested>(_onSignupOtpResendRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
  }

  final AuthRepository _authRepository;

  Future<void> _onSessionCheckRequested(
    AuthSessionCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthAuthenticating(checkingSession: true));
    final user = await _authRepository.restoreSession();

    if (user != null) {
      emit(AuthAuthenticated(user));
      return;
    }

    try {
      final refreshedUser = await _authRepository.refreshSessionIfPossible();
      if (refreshedUser != null) {
        emit(AuthAuthenticated(refreshedUser));
        return;
      }
    } catch (_) {
      // Ignore refresh failures at startup and continue to unauthenticated.
    }

    emit(const AuthUnauthenticated());
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthAuthenticating());

    try {
      final response = await _authRepository.login(
        email: event.email,
        password: event.password,
      );
      emit(AuthAuthenticated(response.user));
    } on ApiException catch (e) {
      emit(AuthFailure(e.message));
    } catch (_) {
      emit(const AuthFailure('Unable to login. Please try again.'));
    }
  }

  Future<void> _onSignupRequested(
    AuthSignupRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthAuthenticating());

    try {
      final challenge = await _authRepository.requestSignupOtp(
        name: event.name,
        email: event.email,
        password: event.password,
      );
      emit(
        AuthOtpRequired(
          signupToken: challenge.signupToken,
          email: challenge.email,
          message: challenge.devOtp != null
              ? 'Dev mode — use code: ${challenge.devOtp}'
              : 'OTP sent to ${challenge.email}.',
          devOtp: challenge.devOtp,
        ),
      );
    } on ApiException catch (e) {
      final message = e.message.toLowerCase();
      final missingOtpToken =
          message.contains('signup otp token missing') ||
          message.contains('otp token missing in server response');
      if (missingOtpToken) {
        emit(
          const AuthFailure(
            'Signup verification failed: OTP challenge was not returned. Please retry signup.',
          ),
        );
        return;
      }
      emit(AuthFailure(e.message));
    } catch (_) {
      emit(const AuthFailure('Could not create account right now.'));
    }
  }

  Future<void> _onGoogleRequested(
    AuthGoogleRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthAuthenticating());
    try {
      final response = await _authRepository.loginWithGoogle();
      emit(AuthAuthenticated(response.user));
    } on ApiException catch (e) {
      emit(AuthFailure(e.message));
    } catch (_) {
      emit(const AuthFailure('Google sign-in failed. Check setup and try again.'));
    }
  }

  Future<void> _onSignupOtpVerificationRequested(
    AuthSignupOtpVerificationRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthAuthenticating());
    try {
      final response = await _authRepository.verifySignupOtp(
        signupToken: event.signupToken,
        otp: event.otp,
      );
      emit(AuthAuthenticated(response.user));
    } on ApiException catch (e) {
      emit(AuthFailure(e.message));
    } catch (_) {
      emit(const AuthFailure('Could not verify OTP right now.'));
    }
  }

  Future<void> _onSignupOtpResendRequested(
    AuthSignupOtpResendRequested event,
    Emitter<AuthState> emit,
  ) async {
    final current = state;
    if (current is! AuthOtpRequired) {
      return;
    }
    try {
      await _authRepository.resendSignupOtp(signupToken: event.signupToken);
      emit(
        AuthOtpRequired(
          signupToken: current.signupToken,
          email: current.email,
          message: 'A new OTP has been sent to ${current.email}.',
        ),
      );
    } on ApiException catch (e) {
      emit(AuthFailure(e.message));
      emit(current);
    } catch (_) {
      emit(const AuthFailure('Failed to resend OTP.'));
      emit(current);
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _authRepository.logout();
    emit(const AuthUnauthenticated());
  }
}
