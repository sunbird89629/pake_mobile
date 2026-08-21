import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pake_shell/src/update/update_check.dart';

/// 造一条 release。默认是「属于 4kvm 的正式版，挂着一个 apk」。
Map<String, Object?> release(
  String tag, {
  bool draft = false,
  bool prerelease = false,
  List<String> assets = const ['app.apk'],
  String body = '',
  String htmlUrl = 'https://github.com/o/r/releases/tag',
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'body': body,
  'html_url': htmlUrl,
  'assets': [
    for (final name in assets)
      {'name': name, 'browser_download_url': 'https://dl/$name'},
  ],
};

UpdateInfo? pick(List<Object?> releases, {String current = '1.0.0'}) =>
    pickUpdate(
      body: jsonEncode(releases),
      bundleId: 'com.pake.fourkvm',
      currentVersion: current,
    );

void main() {
  group('tagPrefixFor', () {
    test('takes the last segment of the bundle id', () {
      expect(tagPrefixFor('com.pake.fourkvm'), 'fourkvm');
      expect(tagPrefixFor('fourkvm'), 'fourkvm');
    });
  });

  group('compareVersions', () {
    test('compares numerically, not lexically', () {
      expect(compareVersions([1, 10, 0], [1, 2, 0]), greaterThan(0));
      expect(compareVersions([1, 2, 0], [1, 10, 0]), lessThan(0));
    });

    test('pads missing segments with zero', () {
      expect(compareVersions([1, 2], [1, 2, 0]), 0);
      expect(compareVersions([2], [1, 9, 9]), greaterThan(0));
    });
  });

  group('parseVersion', () {
    test('rejects what it cannot read rather than guessing', () {
      expect(parseVersion('1.2.0'), [1, 2, 0]);
      expect(parseVersion('1.2'), [1, 2]);
      expect(parseVersion('1.2.3.4'), isNull);
      expect(parseVersion('1.2.0-beta'), isNull);
      expect(parseVersion('v1.2.0'), isNull);
      expect(parseVersion(''), isNull);
    });
  });

  group('parseTag', () {
    test('only accepts its own prefix', () {
      expect(parseTag('fourkvm-v1.2.0', 'fourkvm'), [1, 2, 0]);
      expect(parseTag('youtube-v9.9.9', 'fourkvm'), isNull);
      expect(parseTag('v1.2.0', 'fourkvm'), isNull);
    });
  });

  group('pickUpdate', () {
    test('finds a newer release for this app', () {
      final info = pick([release('fourkvm-v1.2.0')]);

      expect(info!.version, '1.2.0');
      expect(info.tag, 'fourkvm-v1.2.0');
      expect(info.downloadUrl, 'https://dl/app.apk');
    });

    test('ignores releases belonging to other apps in the same repo', () {
      expect(pick([release('youtube-v9.9.9')]), isNull);
    });

    test('skips drafts and prereleases', () {
      expect(pick([release('fourkvm-v2.0.0', draft: true)]), isNull);
      expect(pick([release('fourkvm-v2.0.0', prerelease: true)]), isNull);
    });

    test('returns null when the installed build is newer', () {
      expect(pick([release('fourkvm-v1.2.0')], current: '1.3.0'), isNull);
      expect(pick([release('fourkvm-v1.2.0')], current: '1.2.0'), isNull);
    });

    // 列表按创建时间倒序：给旧版本补发一次 release 会让它排到最前面。
    test('takes the highest version, not the first entry', () {
      final info = pick([
        release('fourkvm-v1.1.0'),
        release('fourkvm-v1.9.0'),
        release('fourkvm-v1.2.0'),
      ]);

      expect(info!.version, '1.9.0');
    });

    // pakem build 走 --split-per-abi，一次出三个包；x86_64 装到真手机上必失败。
    test('picks the arm64 build out of the abi splits', () {
      final info = pick([
        release(
          'fourkvm-v1.2.0',
          assets: [
            'app-x86_64-release.apk',
            'app-armeabi-v7a-release.apk',
            'app-arm64-v8a-release.apk',
          ],
        ),
      ]);

      expect(info!.downloadUrl, 'https://dl/app-arm64-v8a-release.apk');
    });

    test('falls back to any apk when nothing names an abi', () {
      final info = pick([
        release('fourkvm-v1.2.0', assets: ['app.ipa', 'app.apk', 'notes.txt']),
      ]);

      expect(info!.downloadUrl, 'https://dl/app.apk');
    });

    test('falls back to the release page when there is no apk', () {
      final info = pick([
        release('fourkvm-v1.2.0', assets: ['app.ipa'], htmlUrl: 'https://page'),
      ]);

      expect(info!.downloadUrl, 'https://page');
    });

    test('drops a release with nowhere to go', () {
      final info = pick([
        {'tag_name': 'fourkvm-v1.2.0', 'assets': <Object?>[]},
      ]);

      expect(info, isNull);
    });

    test('carries release notes through', () {
      final info = pick([release('fourkvm-v1.2.0', body: '修了 X')]);

      expect(info!.notes, '修了 X');
    });

    // 任何异常在这条路径上都只意味着「这次没查到」，不该冒泡。
    test('returns null on malformed payloads instead of throwing', () {
      for (final body in ['', 'not json', '{}', '[1, 2, 3]', '[null]']) {
        expect(
          pickUpdate(
            body: body,
            bundleId: 'com.pake.fourkvm',
            currentVersion: '1.0.0',
          ),
          isNull,
          reason: 'body: $body',
        );
      }
    });

    test('returns null when the local version is unparseable', () {
      expect(pick([release('fourkvm-v9.9.9')], current: 'dev'), isNull);
    });
  });

  group('releasesEndpoint', () {
    test('asks for a full page from the main repo', () {
      expect(
        releasesEndpoint().toString(),
        'https://api.github.com/repos/sunbird89629/pake_mobile'
        '/releases?per_page=100',
      );
    });
  });
}
