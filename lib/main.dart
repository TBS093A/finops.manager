import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'data/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await Store.open();
  runApp(FinOpsApp(store: store));
  // The P2P node starts in the background; planning works offline.
  unawaited(store.startNetwork());
}
