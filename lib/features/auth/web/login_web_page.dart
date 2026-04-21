import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/colors.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class LoginWebPage extends StatefulWidget {
  const LoginWebPage({super.key});

  @override
  State<LoginWebPage> createState() => _LoginWebPageState();
}

class _LoginWebPageState extends State<LoginWebPage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isRegistering = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleAuth() {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields'), backgroundColor: AppColors.bear),
      );
      return;
    }

    if (_isRegistering) {
      context.read<AuthBloc>().add(AuthRegisterRequested(email: email, password: password));
    } else {
      context.read<AuthBloc>().add(AuthLoginRequested(email: email, password: password));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!), backgroundColor: AppColors.bear),
            );
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 900;
            
            if (isMobile) {
              return _buildMobileLayout();
            }
            
            return _buildDesktopLayout();
          },
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Side: Branding with Advanced Neural Plexus Animation
          Expanded(
            flex: 6,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: NeuralPlexusPainter(_animationController.value),
                      );
                    },
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        AppColors.background.withOpacity(0.4),
                        AppColors.background,
                      ],
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(80.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'KINETIC',
                          style: TextStyle(
                            fontSize: 100,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -6,
                            height: 0.9,
                          ),
                        ),
                        Text(
                          'QUANTUM AI TRADING ENGINE',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            letterSpacing: 8,
                          ),
                        ),
                        SizedBox(height: 60),
                        _FeatureItem(icon: Icons.auto_awesome, text: 'Neural-Network Driven Signals'),
                        _FeatureItem(icon: Icons.speed, text: 'Zero-Latency Execution'),
                        _FeatureItem(icon: Icons.hub, text: 'Global Liquidity Aggregation'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Right Side: Login Form
          Expanded(
            flex: 4,
            child: Container(
              color: AppColors.surface,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _buildAuthForm(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return CustomPaint(
                painter: NeuralPlexusPainter(_animationController.value),
              );
            },
          ),
        ),
        Container(
          color: AppColors.background.withOpacity(0.8),
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: _buildAuthForm(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _isRegistering ? 'CREATE ACCOUNT' : 'SYSTEM ACCESS',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        Text(
          _isRegistering ? 'Join the next generation of trading' : 'Authorize your session to continue',
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
        const SizedBox(height: 48),
        _buildTextField(
          controller: _emailController,
          label: 'EMAIL ADDRESS',
          icon: Icons.email_outlined,
        ),
        const SizedBox(height: 20),
        _buildTextField(
          controller: _passwordController,
          label: 'ACCESS KEY / PASSWORD',
          icon: Icons.lock_outline,
          isObscure: true,
        ),
        const SizedBox(height: 32),
        _buildMainAuthBtn(),
        const SizedBox(height: 24),
        const Row(
          children: [
            Expanded(child: Divider(color: Colors.white10)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('OR', style: TextStyle(color: Colors.white24, fontSize: 10)),
            ),
            Expanded(child: Divider(color: Colors.white10)),
          ],
        ),
        const SizedBox(height: 24),
        _buildGoogleBtn(context),
        const SizedBox(height: 40),
        Center(
          child: TextButton(
            onPressed: () {
              setState(() {
                _isRegistering = !_isRegistering;
              });
            },
            child: Text(
              _isRegistering ? 'ALREADY HAVE AN ACCOUNT? LOGIN' : 'REQUEST ACCESS KEY',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isObscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isObscure,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: AppColors.primary.withOpacity(0.5), size: 20),
            filled: true,
            fillColor: Colors.white.withOpacity(0.03),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary, width: 1),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildMainAuthBtn() {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final isLoading = state.status == AuthStatus.loading;
        return ElevatedButton(
          onPressed: isLoading ? null : _handleAuth,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          child: isLoading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : Text(
                  _isRegistering ? 'CREATE ACCOUNT' : 'SECURE LOGIN',
                  style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 14),
                ),
        );
      },
    );
  }

  Widget _buildGoogleBtn(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final isLoading = state.status == AuthStatus.loading;
        
        return InkWell(
          onTap: isLoading ? null : () => context.read<AuthBloc>().add(AuthGoogleSignInRequested()),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/google_logo.png', height: 22),
                const SizedBox(width: 12),
                const Text(
                  'CONTINUE WITH GOOGLE',
                  style: TextStyle(
                    color: Color(0xFF1F1F1F),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class NeuralPlexusPainter extends CustomPainter {
  final double animationValue;
  final List<Offset> nodes = [];
  final List<double> nodeRadii = [];
  static const int nodeCount = 40;

  NeuralPlexusPainter(this.animationValue) {
    final random = math.Random(42);
    for (int i = 0; i < nodeCount; i++) {
      nodes.add(Offset(random.nextDouble(), random.nextDouble()));
      nodeRadii.add(random.nextDouble() * 2 + 1);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withOpacity(0.2)
      ..strokeWidth = 0.5;

    final glowPaint = Paint()
      ..color = AppColors.primary.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final List<Offset> scaledNodes = nodes.map((n) {
      double dx = (n.dx * size.width + math.sin(animationValue * 2 * math.pi + n.dx * 100) * 20);
      double dy = (n.dy * size.height + math.cos(animationValue * 2 * math.pi + n.dy * 100) * 20);
      return Offset(dx, dy);
    }).toList();

    for (int i = 0; i < nodeCount; i++) {
      for (int j = i + 1; j < nodeCount; j++) {
        double dist = (scaledNodes[i] - scaledNodes[j]).distance;
        if (dist < 150) {
          paint.color = AppColors.primary.withOpacity((1 - dist / 150) * 0.15);
          canvas.drawLine(scaledNodes[i], scaledNodes[j], paint);
        }
      }
    }

    for (int i = 0; i < nodeCount; i++) {
      canvas.drawCircle(scaledNodes[i], nodeRadii[i], paint..color = AppColors.primary.withOpacity(0.5));
      if (i % 5 == 0) {
        canvas.drawCircle(scaledNodes[i], nodeRadii[i] + 2, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant NeuralPlexusPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 20),
          Flexible(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
