import 'package:flutter/material.dart';

import 'app.dart';
import 'data/focus_store.dart';
import 'state/wallet_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await FocusStore.open();
  final wallet = WalletController(store: store);
  await wallet.pruneExpired();
  runApp(FocusArApp(wallet: wallet));
}
