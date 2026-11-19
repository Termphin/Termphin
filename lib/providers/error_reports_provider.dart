import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app/error_reports.dart';

/// Indirection so tests can supply their own reports.
final errorReportsProvider = Provider<ErrorReports>(
  (ref) => ErrorReports.instance,
);
