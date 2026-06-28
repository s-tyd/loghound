import 'package:loghound/loghound.dart';

void main() {
  LogHound.run(
    appId: 'guide-app',
    flavor: 'staging',
    app: () {
      LogHound.screen('Home', route: '/');
      LogHound.action('search.submit', data: {'query': 'ramen'});

      // In a Flutter app, call runApp here:
      // runApp(const App());
    },
  );
}
