import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/validators.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/primary_button.dart';
import '../../../widgets/skeleton.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import 'auth_scaffold.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _acceptedTerms = false;
  String? _inlineError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_acceptedTerms) {
      setState(() => _inlineError = 'Please accept the terms to continue.');
      return;
    }

    setState(() => _inlineError = null);

    context.read<AuthBloc>().add(
      AuthSignupRequested(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthFailure) {
          setState(() => _inlineError = state.message);
          return;
        }
        if (state is AuthOtpRequired) {
          final token = Uri.encodeComponent(state.signupToken);
          final email = Uri.encodeComponent(state.email);
          final devParam = state.devOtp != null
              ? '&dev=${Uri.encodeComponent(state.devOtp!)}'
              : '';
          context.go('/verify-signup?token=$token&email=$email$devParam');
        }
      },
      child: AuthScaffold(
        title: 'Create Account',
        subtitle: 'Set up your profile and start tracking cattle health.',
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: _nameController,
                label: 'Full name',
                prefixIcon: Icons.person_outline_rounded,
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    Validators.required(value, label: 'Full name'),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _emailController,
                label: 'Email',
                prefixIcon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: Validators.email,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _passwordController,
                label: 'Password',
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: true,
                textInputAction: TextInputAction.next,
                validator: Validators.password,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _confirmController,
                label: 'Confirm password',
                prefixIcon: Icons.lock_person_outlined,
                obscureText: true,
                textInputAction: TextInputAction.done,
                validator: (value) {
                  if (value.isEmpty) {
                    return 'Please confirm your password';
                  }
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _acceptedTerms,
                onChanged: (value) {
                  setState(() => _acceptedTerms = value ?? false);
                },
                title: const Text('I agree to the terms and privacy policy'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                child: _inlineError == null
                    ? const SizedBox.shrink(key: ValueKey('no-error'))
                    : Padding(
                        key: ValueKey(_inlineError),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _inlineError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
              ),
              BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  final loading =
                      state is AuthAuthenticating && !state.checkingSession;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrimaryButton(
                        label: 'Create account',
                        icon: Icons.person_add_alt_rounded,
                        isLoading: loading,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: loading
                              ? null
                              : () {
                                  setState(() => _inlineError = null);
                                  context.read<AuthBloc>().add(const AuthGoogleRequested());
                                },
                          icon: const Icon(Icons.account_circle_outlined),
                          label: const Text('Sign up with Google'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: loading ? null : () => context.go('/login'),
                        child: const Text('Already have an account? Login'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    final loading =
                        state is AuthAuthenticating && !state.checkingSession;
                    return loading
                        ? const Center(
                            key: ValueKey('creating-account'),
                            child: SkeletonBox(
                              width: 210,
                              height: 12,
                              radius: 8,
                            ),
                          )
                        : Text(
                            key: const ValueKey('signup-tip'),
                            'Use a password with at least 8 characters.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
