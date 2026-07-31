import 'package:args/command_runner.dart';

import 'commands/build.dart';
import 'commands/doctor.dart';
import 'commands/icon.dart';
import 'commands/init.dart';
import 'output.dart';

CommandRunner<int> buildRunner(Output output) {
  return CommandRunner<int>('pakem', 'Build any web page into a mobile app.')
    ..argParser.addFlag(
      'json',
      negatable: false,
      help: 'Emit machine-readable JSON output instead of human-readable text.',
    )
    ..addCommand(InitCommand(output))
    ..addCommand(BuildCommand(output))
    ..addCommand(DoctorCommand(output))
    ..addCommand(IconCommand(output));
}
