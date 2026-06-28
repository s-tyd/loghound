# loghound examples

Start a local receiver first:

```bash
dart run loghound:loghound stay --host 127.0.0.1 --port 8765 --root logs/loghound
```

Then try one of these examples:

- [`client.dart`](client.dart): sends a single JSON log with `LogHoundClient`.
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
