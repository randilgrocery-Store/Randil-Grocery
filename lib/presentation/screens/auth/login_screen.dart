import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/custom_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late AnimationController _entranceController;
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<Offset> _titleSlide;
  late Animation<double> _titleFade;
  late Animation<double> _fieldsFade;
  late Animation<Offset> _fieldsSlide;
  late Animation<double> _buttonFade;
  late Animation<Offset> _buttonSlide;
  bool _isLoading = false;
  String? _errorMessage;
  bool _showPassword = false;

  Animation<double> _interval(Animation<double> parent,
      {required double start, required double end}) =>
      CurvedAnimation(
        parent: parent,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 950),
      vsync: this,
    )..forward();

    _logoFade = _interval(_entranceController, start: 0.0, end: 0.45);
    _logoScale = Tween<double>(begin: 0.7, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Interval(0.0, 0.45, curve: Curves.easeOutBack),
      ),
    );
    _titleFade = _interval(_entranceController, start: 0.15, end: 0.5);
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(_interval(_entranceController, start: 0.15, end: 0.5));
    _fieldsFade = _interval(_entranceController, start: 0.3, end: 0.72);
    _fieldsSlide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(_interval(_entranceController, start: 0.3, end: 0.72));
    _buttonFade = _interval(_entranceController, start: 0.55, end: 1.0);
    _buttonSlide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(_interval(_entranceController, start: 0.55, end: 1.0));
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      _usernameController.text,
      _passwordController.text,
    );

    if (mounted) {
      if (success) {
        // Navigate to home based on user role
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Invalid username or password';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: PosAppTheme.bgColor,
        body: Center(
          child: SingleChildScrollView(
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo/Header
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: PosAppTheme.primaryGreen.withOpacity(0.25),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(
                          'assets/images/randil_logo.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: _titleFade,
                    child: SlideTransition(
                      position: _titleSlide,
                      child: Column(
                        children: [
                          const Text(
                            'Randil Grocery POS',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: PosAppTheme.textDark,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Point of Sale System',
                            style: TextStyle(
                                fontSize: 14, color: PosAppTheme.textGray),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  FadeTransition(
                    opacity: _fieldsFade,
                    child: SlideTransition(
                      position: _fieldsSlide,
                      child: Column(
                        children: [
                          // Error Message
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                        begin: const Offset(0, -0.2),
                                        end: Offset.zero)
                                    .animate(animation),
                                child: child,
                              ),
                            ),
                            child: _errorMessage != null
                                ? Container(
                                    key: const ValueKey('login_error'),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          PosAppTheme.dangerRed.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: PosAppTheme.dangerRed
                                            .withOpacity(0.5),
                                      ),
                                    ),
                                    child: Text(
                                      _errorMessage!,
                                      style: const TextStyle(
                                        color: PosAppTheme.dangerRed,
                                        fontSize: 12,
                                      ),
                                    ),
                                  )
                                : const SizedBox(
                                    key: ValueKey('login_ok'),
                                    width: double.infinity,
                                  ),
                          ),
                          const SizedBox(height: 16),

                          // Username Field
                          GroceryTextField(
                            label: 'Username',
                            hint: 'Enter your username',
                            controller: _usernameController,
                            prefixIcon: Icons.person,
                          ),
                          const SizedBox(height: 20),

                          // Password Field
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Password',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: PosAppTheme.textDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: !_showPassword,
                                decoration: InputDecoration(
                                  hintText: 'Enter your password',
                                  prefixIcon: const Icon(Icons.lock),
                                  suffixIcon: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _showPassword = !_showPassword;
                                      });
                                    },
                                    child: Icon(
                                      _showPassword
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Login Button
                  FadeTransition(
                    opacity: _buttonFade,
                    child: SlideTransition(
                      position: _buttonSlide,
                      child: GroceryButton(
                        label: 'Login',
                        onPressed: _handleLogin,
                        isLoading: _isLoading,
                        width: double.infinity,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}