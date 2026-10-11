import 'tag_migration_service.dart';

/// Testing switch: re-offers the what's-new popup and the tag conversion on
/// every launch instead of once, and stands in sample tags on a device that
/// has none.
///
/// **Set this back to `false` before a release.** Every read of it is also
/// guarded by `kDebugMode`, so a release build ignores it whatever it says
/// here - but leaving it on still means every debug run is interrupted twice.
const bool kForceInterstitials = true;

/// What the conversion dialog is shown when forced on a device with no tags.
///
/// A fresh install is the normal case for testing this, and there is nothing
/// to look at otherwise. Marked [TagMigrationPlan.isSample] so applying it
/// creates the groups that were ticked and touches nothing else - a stand-in
/// must not rewrite the tester's real data.
TagMigrationPlan sampleTagMigrationPlan() => const TagMigrationPlan(
  isSample: true,
  recordCount: 7,
  tags: [
    TagCandidate(name: 'production', profileCount: 3, snippetCount: 0),
    TagCandidate(name: 'eu-west', profileCount: 1, snippetCount: 1),
    TagCandidate(name: 'staging', profileCount: 1, snippetCount: 0),
    TagCandidate(name: 'personal', profileCount: 0, snippetCount: 1),
  ],
);
