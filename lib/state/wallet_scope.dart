import 'package:flutter/widgets.dart';

import 'wallet_controller.dart';

/// Hands the single [WalletController] down the tree and rebuilds anything
/// that reads it when the balance moves.
class WalletScope extends InheritedNotifier<WalletController> {
  const WalletScope({
    required WalletController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static WalletController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<WalletScope>();
    assert(scope?.notifier != null, 'No WalletScope found above this widget.');
    return scope!.notifier!;
  }
}
