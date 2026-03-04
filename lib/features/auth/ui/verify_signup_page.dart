import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/validators.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/primary_button.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import 'auth_scaffold.dart';

class VerifySignupPage extends StatefulWidget {
  const VerifySignupPage({
    super.key,
    required this.signupToken,
    required this.email,
    this.devOtp,
  });

  final String signupToken;
  final String email;
  final String? devOtp;

  @override
  State<VerifySignupPage> createState() => _VerifySignupPageState();
}

class _VerifySignupPageState extends State<VerifySignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  String? _inlineError;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _inlineError = null);
    context.read<AuthBloc>().add(
      AuthSignupOtpVerificationRequested(
        signupToken: widget.signupToken,
        otp: _otpController.text.trim(),
      ),
    );
  }

  void _resend() {
    context.read<AuthBloc>().add(
      AuthSignupOtpResendRequested(signupToken: widget.signupToken),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.devOtp != null) {
      _otpController.text = widget.devOtp!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthFailure) {
          setState(() => _inlineError = state.message);
          return;
        }
        if (state is AuthOtpRequired && state.message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message!)),
          );
        }
      },
      child: AuthScaffold(
        title: 'Verify Email',
        subtitle: widget.devOtp != null
            ? 'Dev mode: email not sent. Code pre-filled below.'
            : 'Enter the OTP sent to ${widget.email}.',
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.devOtp != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    border: Border.all(color: Colors.amber.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.developer_mode, color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Dev code: ${widget.devOtp}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              AppTextField(
                controller: _otpController,
                label: 'OTP code',
                hint: '6-digit code',
                prefixIcon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                validator: (value) {
                  final required = Validators.required(value, label: 'OTP');
                  if (required != null) {
                    return required;
                  }
                  final normalized = value.trim();
                  if (normalized.length < 4 || normalized.length > 8) {
                    return 'Enter a valid OTP code';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              if (_inlineError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _inlineError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  final loading = state is AuthAuthenticating;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrimaryButton(
                        label: 'Verify and continue',
                        icon: Icons.check_circle_outline_rounded,
                        isLoading: loading,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: loading ? null : _resend,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Resend OTP'),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: loading ? null : () => context.go('/signup'),
                        child: const Text('Back to signup'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
