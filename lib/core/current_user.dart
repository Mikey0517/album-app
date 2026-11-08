import 'package:flutter/foundation.dart';

import '../models/app_user.dart';

class CurrentUser {
  static final ValueNotifier<AppUser?> notifier = ValueNotifier<AppUser?>(null);
}
