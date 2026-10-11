import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/ssh/local_network_permission.dart';

void main() {
  InternetAddress ip(String value) => InternetAddress(value);

  group('isLocalNetworkAddress', () {
    test('the private IPv4 ranges are local', () {
      expect(isLocalNetworkAddress(ip('10.0.0.5')), isTrue);
      expect(isLocalNetworkAddress(ip('192.168.1.10')), isTrue);
      expect(isLocalNetworkAddress(ip('172.16.0.1')), isTrue);
      expect(isLocalNetworkAddress(ip('172.31.255.254')), isTrue);
      expect(isLocalNetworkAddress(ip('169.254.3.4')), isTrue);
    });

    test('the addresses either side of 172.16/12 are not', () {
      expect(isLocalNetworkAddress(ip('172.15.0.1')), isFalse);
      expect(isLocalNetworkAddress(ip('172.32.0.1')), isFalse);
    });

    test('a VPN peer is not local', () {
      expect(isLocalNetworkAddress(ip('100.64.0.1')), isFalse);
      expect(isLocalNetworkAddress(ip('100.101.102.103')), isFalse);
    });

    test('loopback and public addresses are not local', () {
      expect(isLocalNetworkAddress(ip('127.0.0.1')), isFalse);
      expect(isLocalNetworkAddress(ip('8.8.8.8')), isFalse);
      expect(isLocalNetworkAddress(ip('::1')), isFalse);
      expect(isLocalNetworkAddress(ip('2606:4700:4700::1111')), isFalse);
    });

    test('IPv6 link-local and unique-local are local', () {
      expect(isLocalNetworkAddress(ip('fe80::1')), isTrue);
      expect(isLocalNetworkAddress(ip('fd00::1')), isTrue);
      expect(isLocalNetworkAddress(ip('fc00::1')), isTrue);
    });

    test('an IPv4-mapped address carries the v4 rules with it', () {
      expect(isLocalNetworkAddress(ip('::ffff:192.168.1.1')), isTrue);
      expect(isLocalNetworkAddress(ip('::ffff:8.8.8.8')), isFalse);
    });
  });

  group('resolvesToLocalNetwork', () {
    test('a literal is answered without a lookup', () async {
      expect(await resolvesToLocalNetwork('192.168.1.1'), isTrue);
      expect(await resolvesToLocalNetwork('100.64.0.1'), isFalse);
    });

    test('an mDNS name is local whether or not it resolves', () async {
      expect(await resolvesToLocalNetwork('nas.local'), isTrue);
      expect(await resolvesToLocalNetwork('NAS.Local'), isTrue);
      expect(await resolvesToLocalNetwork('nas.local.'), isTrue);
    });

    test('a name that does not resolve is not a permission problem', () async {
      expect(
        await resolvesToLocalNetwork('termphin-does-not-exist.invalid'),
        isFalse,
      );
    });
  });

  group('allOnLocalNetwork', () {
    test('every candidate local is the blocked case', () async {
      expect(await allOnLocalNetwork(['192.168.1.5', '10.0.0.2']), isTrue);
    });

    test('one candidate off the LAN leaves somewhere to go', () async {
      expect(await allOnLocalNetwork(['192.168.1.5', '8.8.8.8']), isFalse);
      expect(await allOnLocalNetwork(['100.64.0.1', '192.168.1.5']), isFalse);
    });

    test('no candidates at all is not blocked', () async {
      expect(await allOnLocalNetwork(const []), isFalse);
    });
  });
}
