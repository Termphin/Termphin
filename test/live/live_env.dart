import 'package:shared_preferences/shared_preferences.dart';
import 'package:termphin/services/ssh/ssh_prompts.dart';

import '../support/secure_storage_channel.dart';

/// Stands up the two platform services `SshService.connect` reaches through on
/// its way to verifying a host key, neither of which exists under
/// `flutter test`: SharedPreferences, where `KnownHostsStore` keeps the pins,
/// and the Keystore behind `SecretCipher`, which seals them.
///
/// Call from `setUpAll`, not `setUp` - [mockSecureStorage] mints a fresh master
/// key per call, so re-running it mid-file would leave the pins written by
/// earlier tests sealed under a key that is gone.
void initLiveEnv() {
  SharedPreferences.setMockInitialValues({});
  mockSecureStorage();
}

/// The live targets are throwaway containers and VMs, rebuilt whenever the
/// harness feels like it, so their host keys are new every time and there is
/// nothing stable to pin against - this is the harness's
/// `StrictHostKeyChecking=no`.
///
/// Every `connect()` in a live test needs one. Verification runs before
/// authentication and [SshService.verifyHostKey] fails closed, so a connect
/// with no prompt is refused before it ever reaches the password - which is
/// not what any of these tests are about. What the verification decides is
/// covered by `test/services/host_key_verification_test.dart`, against a
/// pinned store rather than a real handshake.
Future<bool> acceptHostKey(HostKeyPromptRequest request) async => true;
