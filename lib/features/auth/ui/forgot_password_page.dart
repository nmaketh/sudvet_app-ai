import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/utils/validators.dart';
import '../data/auth_repository.dart';
import 'auth_scaffold.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _requestFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  bool _requesting = false;
  bool _resetting = false;
  String? _resetToken;
  String? _email;
  String? _inlineError;

  AuthRepository get _authRepository => context.read<AuthRepository>();

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    if (!_requestFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _requesting = true;
      _inlineError = null;
    });

    try {
      final challenge = await _authRepository.requestPasswordResetOtp(
        email: _emailController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _resetToken = challenge.resetToken;
        _email = challenge.email;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OTP sent to ${challenge.email}.')),
      );
    } on ApiException catch (e) {
      setState(() => _inlineError = e.message);
    } catch (_) {
      setState(() => _inlineError = 'Unable to request password reset OTP right now.');
    } finally {
      if (mounted) {
        setState(() => _requesting = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    if (_resetToken == null || _resetToken!.isEmpty) {
      setState(() => _inlineError = 'Request OTP first.');
      return;
    }
    if (!_resetFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _resetting = true;
      _inlineError = null;
    });

    try {
      await _authRepository.resetPasswordWithOtp(
        resetToken: _resetToken!,
        otp: _otpController.text.trim(),
        newPassword: _newPasswordController.text,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset successful. Please login.')),
      );
      context.go('/login');
    } on ApiException catch (e) {
      setState(() => _inlineError = e.message);
    } catch (_) {
      setState(() => _inlineError = 'Unable to reset password right now.');
    } finally {
      if (mounted) {
        setState(() => _resetting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final otpRequested = _resetToken != null && _resetToken!.isNotEmpty;
    return AuthScaffold(
      title: 'Reset Password',
      subtitle: 'Request an OTP code and set a new password securely.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Form(
            key: _requestFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Account email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) => Validators.email(value ?? ''),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _requesting ? null : _requestOtp,
                  icon: _requesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(_requesting ? 'Requesting...' : 'Send reset OTP'),
                ),
              ],
            ),
          ),
          if (otpRequested) ...[
            const SizedBox(height: 18),
            Text(
              'OTP sent to ${_email ?? _emailController.text.trim()}.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Form(
              key: _resetFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'OTP code',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                    validator: (value) {
                      final normalized = (value ?? '').trim();
                      final required = Validators.required(
                        normalized,
                        label: 'OTP',
                      );
                      if (required != null) {
                        return required;
                      }
                      if (normalized.length < 4 || normalized.length > 8) {
                        return 'Enter a valid OTP';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New password',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                    validator: (value) => Validators.password(value ?? ''),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                      prefixIcon: Icon(Icons.lock_person_outlined),
                    ),
                    validator: (value) {
                      final normalized = (value ?? '').trim();
                      if (normalized.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (value != _newPasswordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _resetting ? null : _resetPassword,
                    icon: _resetting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text(_resetting ? 'Resetting...' : 'Reset password'),
                  ),
                ],
              ),
            ),
          ],
          if (_inlineError != null) ...[
            const SizedBox(height: 12),
            Text(
              _inlineError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Back to login'),
          ),
        ],
      ),
    );
  }
}
