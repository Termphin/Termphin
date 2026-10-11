import 'package:termphin/models/port_forwarding_rule.dart';
import 'package:termphin/models/profile_group.dart';
import 'package:termphin/models/snippet.dart';
import 'package:termphin/models/ssh_key.dart';
import 'package:termphin/models/ssh_profile.dart';

SshProfile profileFixture({
  String id = 'profile-1',
  String name = 'Production',
  String host = 'example.com',
  int port = 22,
  String username = 'deploy',
  AuthMethod authMethod = AuthMethod.password,
  String? password = 'secret',
  String? privateKey,
  String? passphrase,
  String? sshKeyId,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? lastConnectedAt,
  List<PortForwardingRule> portForwardings = const [],
  String group = 'General',
  String? iconName = 'desktop',
  String? colorHex = '4DA3FF',
  List<String> fallbackHosts = const [],
  String? lastGoodHost,
  bool mainHostFirst = true,
  String? jumpHostProfileId,
}) {
  final created = createdAt ?? DateTime.utc(2026, 1, 2, 3, 4, 5);
  return SshProfile(
    id: id,
    name: name,
    host: host,
    port: port,
    username: username,
    authMethod: authMethod,
    password: password,
    privateKey: privateKey,
    passphrase: passphrase,
    sshKeyId: sshKeyId,
    createdAt: created,
    updatedAt: updatedAt,
    lastConnectedAt: lastConnectedAt,
    portForwardings: portForwardings,
    group: group,
    iconName: iconName,
    colorHex: colorHex,
    fallbackHosts: fallbackHosts,
    lastGoodHost: lastGoodHost,
    mainHostFirst: mainHostFirst,
    jumpHostProfileId: jumpHostProfileId,
  );
}

PortForwardingRule forwardingRuleFixture({
  String id = 'tunnel-1',
  String? name = 'Database',
  ForwardType type = ForwardType.local,
  int localPort = 5432,
  String remoteHost = 'db.internal',
  int remotePort = 5432,
  String localHost = 'localhost',
  DateTime? createdAt,
}) {
  return PortForwardingRule(
    id: id,
    name: name,
    type: type,
    localPort: localPort,
    remoteHost: remoteHost,
    remotePort: remotePort,
    localHost: localHost,
    createdAt: createdAt ?? DateTime.utc(2026, 2, 3),
  );
}

SshKey sshKeyFixture({
  String id = 'key-1',
  String name = 'Laptop',
  SshKeyType keyType = SshKeyType.ed25519,
  String privateKeyPem = 'private-pem',
  String publicKeyOpenSSH = 'ssh-ed25519 AAAA laptop',
  String group = 'General',
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return SshKey(
    id: id,
    name: name,
    keyType: keyType,
    privateKeyPem: privateKeyPem,
    publicKeyOpenSSH: publicKeyOpenSSH,
    group: group,
    createdAt: createdAt ?? DateTime.utc(2026, 3, 4),
    updatedAt: updatedAt,
  );
}

Snippet snippetFixture({
  String id = 'snippet-1',
  String name = 'Check uptime',
  String command = 'uptime',
  String group = 'General',
  Map<String, String> defaults = const {},
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return Snippet(
    id: id,
    name: name,
    command: command,
    group: group,
    defaults: defaults,
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    updatedAt: updatedAt,
  );
}

ProfileGroup groupFixture({String name = 'General', String? colorHex}) {
  return ProfileGroup(name: name, colorHex: colorHex);
}

/// An ed25519 key generated for tests with `ssh-keygen -N test-pass-123`. It
/// guards nothing: it exists so the encrypted-import path has something real
/// to parse, which no synthetic string can stand in for.
const encryptedEd25519Passphrase = 'test-pass-123';

const encryptedEd25519PublicBlob =
    'AAAAC3NzaC1lZDI1NTE5AAAAIFC+08NCfD76vuiRG3+oOcQe+yyA6zEVrqAnOLUKunMd';

const encryptedEd25519Pem = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABA5ws1rBh
pKNgqqmTDWjKjXAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIFC+08NCfD76vuiR
G3+oOcQe+yyA6zEVrqAnOLUKunMdAAAAoBHvmaK8ro//+fYd0Yco/p0wNPZgw/9BLBE66n
/s0MRu62NMVxtczapZIAFe2yjT2UxrRQQRCIBCz+im2MfD6NkYSE2pyKFVDkt/pyWB+Y/n
3EMnFd3IJ8LNwIfWqtXlqm625y62t+rSUvvmzQ2jLrFKb5fLyjRa+rEvHUi91yo2Fz9cRF
eEM1Hw0ECozYL2yVBSQuYpTKgZYE/F1hytnnk=
-----END OPENSSH PRIVATE KEY-----''';

/// The same, without a passphrase, so a test can tell the two apart.
const unencryptedEd25519Pem = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBXDEJuVU/FpYJ5+PeEN43ylcHfeDpakd7oVmox/t/K3AAAAJgIo0g/CKNI
PwAAAAtzc2gtZWQyNTUxOQAAACBXDEJuVU/FpYJ5+PeEN43ylcHfeDpakd7oVmox/t/K3A
AAAEA3r0PfTGCODYgxxsXFDfkDttsy5Welqp6fgsLaCCsxAFcMQm5VT8Wlgnn494Q3jfKV
wd94OlqR3uhWajH+38rcAAAAE3Rlcm1waGluLXRlc3QtcGxhaW4BAg==
-----END OPENSSH PRIVATE KEY-----''';
