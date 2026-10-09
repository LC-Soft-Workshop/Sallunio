import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/github_updates.dart';
import 'package:tableo/storage.dart';
import 'package:tableo/domain.dart';

void main() {
  test('Numeric versions ignore older, equal and unstable releases', () async {
    expect(isNewerVersion('v1.0.31', '1.0.30'), true);
    expect(isNewerVersion('1.0.100', '1.0.31'), true);
    expect(isNewerVersion('1.0.31', '1.0.31'), false);
    expect(isNewerVersion('1.0.24', '1.0.31'), false);
    final service = GithubUpdateService(
      repository: 'example/tableo',
      installedVersion: '1.0.30',
      fetcher: (_) async => {'tag_name': 'v2.0.0', 'prerelease': true},
    );
    expect(await service.check(), isNull);
  });

  test(
    'Update request contains only public repository; links cannot redirect',
    () async {
      Uri? requested;
      final service = GithubUpdateService(
        repository: 'example/tableo',
        installedVersion: '1.0.30',
        fetcher: (uri) async {
          requested = uri;
          return {
            'tag_name': 'v1.0.31',
            'html_url': 'https://malicious.invalid/download',
          };
        },
      );
      final update = (await service.check())!;
      expect(
        requested.toString(),
        'https://api.github.com/repos/example/tableo/releases/latest',
      );
      expect(
        update.changelogUrl.toString(),
        'https://github.com/example/tableo/releases/tag/v1.0.31',
      );
      expect(update.releaseUrl.host, 'github.com');
    },
  );

  test('Missing repository fails before any network request', () async {
    var called = false;
    final service = GithubUpdateService(
      repository: '',
      installedVersion: '1.0.31',
      fetcher: (_) async {
        called = true;
        return {};
      },
    );
    await expectLater(service.check(), throwsFormatException);
    expect(called, false);
    expect(service.changelogUrl, isNull);
  });

  test('Windows storage never falls back to executable directory', () {
    expect(
      defaultDataDirectory(
        environment: {'APPDATA': r'C:\Users\Fictif\AppData\Roaming'},
      ),
      r'C:\Users\Fictif\AppData\Roaming\Tableo',
    );
    expect(
      () => defaultDataDirectory(environment: {}),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'Version check and reopening preserve existing events exactly',
    () async {
      final dir = await Directory.systemTemp.createTemp('tableo-update-test-');
      final store = Store();
      try {
        await store.open(path: dir.path);
        final project = demoProject();
        project['name'] = 'Événement fictif conservé';
        await store.save(project);
        final before = await store.load();
        final db = File('${dir.path}${Platform.pathSeparator}tableo.sqlite');
        await store.close();
        final bytes = await db.readAsBytes();
        final updater = GithubUpdateService(
          repository: 'example/tableo',
          installedVersion: '1.0.30',
          fetcher: (_) async => {'tag_name': 'v1.0.31'},
        );
        await updater.check();
        expect(await db.readAsBytes(), bytes);
        final reopened = Store();
        await reopened.open(path: dir.path);
        expect(await reopened.load(), before);
        await reopened.close();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
