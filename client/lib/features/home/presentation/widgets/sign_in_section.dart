import 'dart:math' as math;

import 'package:client/features/auth/presentation/widgets/sign_in_options_content.dart';
import 'package:flutter/material.dart';

class HomePageSignInSection extends StatefulWidget {
  const HomePageSignInSection({Key? key}) : super(key: key);

  @override
  _HomePageSignInSectionState createState() => _HomePageSignInSectionState();
}

class _HomePageSignInSectionState extends State<HomePageSignInSection> {
  /// The form's width on anything wide enough to grant it.
  static const double _maxContentWidth = 380;

  /// Kept on both sides once the screen can no longer afford the full width.
  static const double _gutter = 20;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The form used to be a fixed SizedBox(width: 380). A SizedBox
          // clamps to its incoming constraints, so on any screen narrower
          // than that -- an iPhone SE is 375 -- it simply took the full width
          // and the gutters vanished, leaving the fields flush to both edges.
          final width = math.min(
            _maxContentWidth,
            math.max(0.0, constraints.maxWidth - _gutter * 2),
          );

          return Column(
            children: [
              const SizedBox(height: 45),
              SizedBox(
                width: width,
                child: const SignInOptionsContent(showSignUp: true),
              ),
            ],
          );
        },
      ),
    );
  }
}
