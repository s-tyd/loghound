# loghound examples

Run a Flutter app and collect hidden events:

```bash
dart run loghound:loghound run
```

For split terminals, keep the collector running and start Flutter normally:

```bash
dart run loghound:loghound stay
flutter run
```

Examples:

- [`client.dart`](client.dart): emits one hidden VM Service event with
  `LogHoundClient`.
- [`flutter_bootstrap.dart`](flutter_bootstrap.dart): shows the minimal
  `LogHound.run` setup used by Flutter apps.

Minimal app setup:

```dart
import 'package:loghound/loghound.dart';

void main() {
  LogHound.run(
    appId: 'guide-app',
    flavor: 'staging',
    app: () {
      LogHound.action('app.started');
    },
  );
}
```
