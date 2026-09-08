import 'package:flutter/foundation.dart';

import 'stretch_job.dart';

/// Web build: there is no native library to call, and no rehearsal engine to
/// call it for.
///
/// Reached only if something asks for a render on a platform that cannot do
/// one; the caller falls back to the unstretched file either way.
int renderStretchJobs(List<StretchJob> jobs) {
  debugPrint('rehearsal stretch: not available on this platform');
  return -1;
}
