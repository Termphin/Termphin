import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/assistant/server_system.dart';

void main() {
  test('a Linux server names its distribution, shell and editors', () {
    expect(
      describeServerSystem(
        'uname=Linux 6.8.0\ndistro=Ubuntu 24.04 LTS\nshell=/bin/bash\n'
        'has=python3\nhas=perl\n',
        windows: false,
      ),
      'The server runs Ubuntu 24.04 LTS (Linux 6.8.0), shell bash. '
      'python3 and perl are installed.',
    );
  });

  test('a Mac is told its sed is the BSD one', () {
    final text = describeServerSystem(
      'uname=Darwin 24.1.0\nmacos=15.1\nshell=/bin/zsh\nhas=perl\n',
      windows: false,
    )!;
    expect(text, startsWith('The server runs macOS 15.1, shell zsh.'));
    expect(text, contains('perl is installed.'));
    expect(text, contains("sed -i ''"));
  });

  test('a server with neither editor says so', () {
    expect(
      describeServerSystem('uname=Linux 5.10\n', windows: false),
      'The server runs Linux 5.10. Neither python3 nor perl is installed.',
    );
  });

  test('a Windows server is told to use PowerShell', () {
    expect(
      describeServerSystem(
        'windows=Microsoft Windows Server 2022 Standard\r\npowershell=5.1.20348\r\n',
        windows: true,
      ),
      'The server runs Microsoft Windows Server 2022 Standard, PowerShell '
      '5.1.20348. Use PowerShell commands, not POSIX ones.',
    );
  });

  test('an answer that says nothing describes nothing', () {
    expect(describeServerSystem('', windows: false), isNull);
    expect(
      describeServerSystem('bash: uname: not found', windows: false),
      isNull,
    );
    expect(describeServerSystem('', windows: true), isNull);
  });
}
