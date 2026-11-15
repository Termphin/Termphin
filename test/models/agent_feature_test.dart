import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/models/agent_feature.dart';
import 'package:termphin/services/terminal/osc_markers.dart';

void main() {
  group('AgentFeature.missingFor', () {
    test('a master that never said its version misses everything', () {
      expect(AgentFeature.missingFor(null), AgentFeature.values);
    });

    test('a master misses only what came after it', () {
      expect(AgentFeature.missingFor('0.15.0'), [
        AgentFeature.inPlaceUpdates,
        AgentFeature.wentQuietNotice,
        AgentFeature.backgroundNotices,
      ]);
      expect(AgentFeature.missingFor('0.17.0'), [
        AgentFeature.backgroundNotices,
      ]);
    });

    test('a current master misses nothing', () {
      expect(AgentFeature.missingFor('0.18.0'), isEmpty);
      expect(AgentFeature.missingFor('1.0.0'), isEmpty);
    });

    test('a version that does not parse counts as old', () {
      expect(AgentFeature.missingFor('dev'), AgentFeature.values);
    });
  });

  group('masterVersionFrom', () {
    test('reads the version the master names', () {
      expect(masterVersionFrom('5384;termphin-master;0.16.0'), '0.16.0');
    });

    test('ignores other markers and anything malformed', () {
      expect(masterVersionFrom('5383;termphin-offset;1:2'), isNull);
      expect(masterVersionFrom('5384;termphin-master;0.16'), isNull);
      expect(masterVersionFrom('5384;termphin-master;x; rm -rf'), isNull);
    });
  });
}
