import 'package:flutter/material.dart';

import 'state/wallet_controller.dart';
import 'state/wallet_scope.dart';
import 'theme/app_theme.dart';
import 'ui/screens/home_screen.dart';

class FocusArApp extends StatelessWidget {
  const FocusArApp({required this.wallet, super.key});

  final WalletController wallet;

  @override
  Widget build(BuildContext context) {
    return WalletScope(
      controller: wallet,
      child: MaterialApp(
        title: 'FocusAR',
        debugShowCheckedModeBanner: false,
        theme: buildFocusTheme(),
        home: const HomeScreen(),
      ),
    );
  }
}
