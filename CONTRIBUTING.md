# Contributing to Termphin

Thanks for wanting to help. Bug reports and ideas are as welcome as code.

## Reporting bugs and ideas

Use the issue forms at https://github.com/Termphin/Termphin/issues. A
security vulnerability goes to **contact@termphin.dev** instead, never to a
public issue - see [SECURITY.md](SECURITY.md).

## Pull requests

1. For anything larger than a small fix, open an issue first so we can agree
   on the approach before you spend time on it.
2. Keep a pull request to one topic.
3. Run `flutter analyze` and `flutter test` before you push; both must pass.
   A bug fix comes with a test that fails without it.
4. Every user-facing string goes into `lib/i18n/strings_en.i18n.json`, then
   `dart run slang`.
5. The pull request title follows Conventional Commits
   (`type(scope): subject`): pull requests are squashed, so the title becomes
   the commit on `main`. CI (`flutter analyze` and `flutter test`) has to pass
   before it can merge.

## License

Contributions are accepted under the same terms as the rest of the project:
by opening a pull request you license your contribution under the
[GNU General Public License, version 3 or later](LICENSE), together with the
[additional terms](ADDITIONAL-TERMS.md) - among them the permission that lets
the app ship through app stores whose terms conflict with the GPL. There is
nothing to sign. The name and logo are covered separately by the
[trademark policy](TRADEMARKS.md).
