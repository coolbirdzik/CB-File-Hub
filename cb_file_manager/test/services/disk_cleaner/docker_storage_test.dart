import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/disk_cleaner/docker/docker_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// `docker system df --verbose --format json`, trimmed from a real run.
final verboseJson = jsonEncode({
  'Images': [
    {
      'Containers': '1',
      'ID': 'sha256:aaaaaaaaaaaaaaaa',
      'Repository': 'postgres',
      'Tag': '16',
      'Size': '450MB',
      'SharedSize': '0B',
      'UniqueSize': '450MB',
    },
    {
      'Containers': '0',
      'ID': 'sha256:bbbbbbbbbbbbbbbb',
      'Repository': 'app/web',
      'Tag': 'old',
      'Size': '221MB',
      'SharedSize': '121.4MB',
      'UniqueSize': '99.76MB',
    },
    {
      'Containers': '0',
      'ID': 'sha256:cccccccccccccccc',
      'Repository': '<none>',
      'Tag': '<none>',
      'Size': '70MB',
      'SharedSize': '13.33MB',
      'UniqueSize': '56.67MB',
    },
  ],
  'Containers': [
    {
      'ID': '1',
      'Names': 'db',
      'Image': 'postgres:16',
      'State': 'running',
      'Size': '2B (virtual 450MB)',
    },
    {
      'ID': '2',
      'Names': 'job',
      'Image': 'app/web:old',
      'State': 'exited',
      'Size': '380.9kB',
    },
  ],
  'Volumes': [
    {'Name': 'db-data', 'Links': '1', 'Size': '1.2GB'},
    {'Name': 'old-cache', 'Links': '0', 'Size': '820.9kB'},
  ],
  'BuildCache': [
    {
      'ID': 'x',
      'Description': 'npm install',
      'Size': '3GB',
      'InUse': 'false',
      'LastUsedAt': '2026-06-11 09:42:58.017101834 +0000 UTC',
    },
    {'ID': 'y', 'Description': 'go build', 'Size': '1GB', 'InUse': 'true'},
  ],
});

const summaryJson = '''
{"Active":"1","Reclaimable":"156.4MB (21%)","Size":"741.8MB","TotalCount":"3","Type":"Images"}
{"Active":"1","Reclaimable":"380.9kB (99%)","Size":"380.9kB","TotalCount":"2","Type":"Containers"}
{"Active":"1","Reclaimable":"820.9kB (0%)","Size":"1.201GB","TotalCount":"2","Type":"Local Volumes"}
{"Active":"0","Reclaimable":"3GB","Size":"4GB","TotalCount":"2","Type":"Build Cache"}
''';

class _Docker {
  final calls = <List<String>>[];
  final responses = <String, ProcessResult>{};

  Future<ProcessResult> run(String executable, List<String> args) async {
    calls.add(args);
    final key = args.take(2).join(' ');
    return responses[key] ??
        responses[args.join(' ')] ??
        ProcessResult(0, 0, '', '');
  }
}

void main() {
  test('sizes in Docker units', () {
    expect(DockerTool.parseSize('13.86GB'), 13860000000);
    expect(DockerTool.parseSize('380.9kB'), 380900);
    expect(DockerTool.parseSize('89B'), 89);
    expect(DockerTool.parseSize('1.5GiB'), (1.5 * 1024 * 1024 * 1024).round());
    expect(DockerTool.parseSize('N/A'), 0);
    expect(
      DockerTool.reclaimedBytes(
        'Deleted: sha256:x\nTotal reclaimed space: 1.2GB',
      ),
      1200000000,
    );
    expect(DockerTool.reclaimedBytes('Total: 3GB'), 3000000000);
  });

  test('reads images, containers, volumes and build cache', () {
    final report = DockerTool.parse(verboseJson, summary: summaryJson);
    expect(report.status, DockerStatus.ready);
    expect(report.images.map((i) => i.name), [
      'postgres:16',
      'app/web:old',
      'cccccccccccc',
    ]);
    expect(report.images.last.isDangling, isTrue);
    // Docker's own totals win over sums of the lists.
    expect(report.imageBytes, 741800000);
    expect(report.volumeBytes, 1201000000);
    expect(report.buildCacheBytes, 4000000000);

    expect(report.countOf(DockerCleanKind.stoppedContainers), 1);
    expect(report.bytesOf(DockerCleanKind.stoppedContainers), 380900);
    expect(report.countOf(DockerCleanKind.danglingImages), 1);
    expect(report.bytesOf(DockerCleanKind.danglingImages), 56670000);
    expect(report.countOf(DockerCleanKind.unusedImages), 2);
    expect(report.bytesOf(DockerCleanKind.unusedImages), 156400000);
    expect(report.countOf(DockerCleanKind.buildCache), 1);
    expect(report.bytesOf(DockerCleanKind.buildCache), 3000000000);
    expect(report.countOf(DockerCleanKind.unusedVolumes), 1);
    expect(report.cleanable, DockerCleanKind.values);
    // Only regenerable prunes start checked.
    expect(DockerCleanKind.values.where((k) => k.selectedByDefault), [
      DockerCleanKind.danglingImages,
      DockerCleanKind.buildCache,
    ]);
  });

  test('a stopped daemon and a missing CLI are reported, not errors', () async {
    final docker = _Docker()
      ..responses['system df'] = ProcessResult(
        0,
        1,
        '',
        'Cannot connect to the Docker daemon at unix:///var/run/docker.sock. '
            'Is the docker daemon running?',
      );
    final down = await DockerTool(
      run: docker.run,
      locate: () => '/usr/local/bin/docker',
    ).load();
    expect(down.status, DockerStatus.notRunning);
    final missing = await DockerTool(
      run: docker.run,
      locate: () => null,
    ).load();
    expect(missing.status, DockerStatus.notInstalled);
  });

  test('prunes in order and lets unused images cover dangling ones', () async {
    final docker = _Docker()
      ..responses['image prune'] = ProcessResult(
        0,
        0,
        'Total reclaimed space: 156.4MB',
        '',
      )
      ..responses['builder prune'] = ProcessResult(0, 0, 'Total:\t3GB', '');
    final steps = <DockerCleanKind>[];
    final freed =
        await DockerTool(
          run: docker.run,
          locate: () => '/usr/local/bin/docker',
        ).prune({
          DockerCleanKind.buildCache,
          DockerCleanKind.danglingImages,
          DockerCleanKind.unusedImages,
          DockerCleanKind.stoppedContainers,
        }, onStep: steps.add);
    expect(docker.calls, [
      ['container', 'prune', '--force'],
      ['image', 'prune', '--all', '--force'],
      ['builder', 'prune', '--all', '--force'],
    ]);
    expect(steps, [
      DockerCleanKind.stoppedContainers,
      DockerCleanKind.unusedImages,
      DockerCleanKind.buildCache,
    ]);
    expect(freed[DockerCleanKind.unusedImages], 156400000);
    expect(freed[DockerCleanKind.buildCache], 3000000000);
  });

  test('a failed prune stops and says which', () async {
    final docker = _Docker()
      ..responses['volume prune'] = ProcessResult(
        0,
        1,
        '',
        'permission denied',
      );
    expect(
      () => DockerTool(
        run: docker.run,
        locate: () => 'docker',
      ).prune({DockerCleanKind.unusedVolumes}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('volume prune: permission denied'),
        ),
      ),
    );
  });
}
