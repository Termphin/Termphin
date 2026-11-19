/// Where the public side of the project lives.
///
/// Issues live on the app's own public repository (`Termphin/Termphin`), so a
/// bug report lands somewhere public and searchable rather than in one
/// mailbox. The mailto rows in Settings stay for anything the user would
/// rather not write in the open.
class ProjectUrls {
  const ProjectUrls._();

  static const repository = 'https://github.com/Termphin/Termphin';
  static const issues = '$repository/issues';
  static const contributing = '$repository/blob/main/CONTRIBUTING.md';
  static const license = '$repository/blob/main/LICENSE';

  /// The web account page, where the account can be managed and deleted from
  /// a browser too.
  static const accountPage = 'https://app.termphin.dev';
}
