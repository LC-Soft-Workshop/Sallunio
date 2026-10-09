import 'dart:async';
import 'dart:convert';
import 'dart:io';

const githubRepository = String.fromEnvironment(
  'TABLEO_GITHUB_REPOSITORY',
  defaultValue: 'freakbn777/Tableo',
);

class UpdateInfo {
  final String version;
  final Uri releaseUrl;
  final Uri changelogUrl;
  const UpdateInfo({
    required this.version,
    required this.releaseUrl,
    required this.changelogUrl,
  });
}

abstract class UpdateService {
  Uri? get changelogUrl;
  Future<UpdateInfo?> check();
}

typedef ReleaseFetcher = Future<Map<String, dynamic>> Function(Uri uri);

class GithubUpdateService implements UpdateService {
  final String repository;
  final String installedVersion;
  final ReleaseFetcher? fetcher;
  GithubUpdateService({
    required this.repository,
    required this.installedVersion,
    this.fetcher,
  });

  bool get configured =>
      RegExp(r'^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$').hasMatch(repository) &&
      !repository.endsWith('/..');
  @override
  Uri? get changelogUrl => configured
      ? Uri.https('github.com', '/$repository/blob/main/CHANGELOG.md')
      : null;

  @override
  Future<UpdateInfo?> check() async {
    if (!configured) {
      throw const FormatException(
        'Le dépôt de mises à jour n’est pas encore configuré.',
      );
    }
    final uri = Uri.https(
      'api.github.com',
      '/repos/$repository/releases/latest',
    );
    final release = await (fetcher ?? _getRelease)(uri);
    if (release['draft'] == true || release['prerelease'] == true) return null;
    final tag = release['tag_name'];
    if (tag is! String) {
      throw const FormatException('Réponse de version GitHub invalide.');
    }
    if (!isNewerVersion(tag, installedVersion)) return null;
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    // The remote response cannot redirect the user to a different website.
    final page = Uri.https('github.com', '/$repository/releases/tag/$tag');
    return UpdateInfo(version: version, releaseUrl: page, changelogUrl: page);
  }

  Future<Map<String, dynamic>> _getRelease(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Tableo/$installedVersion',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set('X-GitHub-Api-Version', '2026-03-10');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Versions indisponibles sur GitHub (HTTP ${response.statusCode}).',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024) {
          throw const FormatException('Réponse GitHub trop volumineuse.');
        }
      }
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Réponse GitHub invalide.');
      }
      return value;
    } finally {
      client.close(force: true);
    }
  }
}

bool isNewerVersion(String candidate, String installed) {
  List<int> parse(String value) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$')
        .firstMatch(value);
    if (match == null) {
      throw const FormatException('Numéro de version non reconnu.');
    }
    return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  final a = parse(candidate), b = parse(installed);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}
