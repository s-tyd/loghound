import 'dart:io';

import 'package:loghound/src/cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runLogHoundCli(args);
}
