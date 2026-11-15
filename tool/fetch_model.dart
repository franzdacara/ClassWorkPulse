// Downloads the on-device model into assets/models/ so it gets bundled into
// the app. The file is too large for git, so run this once after cloning:
//
//   dart run tool/fetch_model.dart
//
// To ship a different model, put any chat-capable .gguf file in assets/models/
// instead (keep a single .gguf there).
import 'dart:io';

import 'package:crypto/crypto.dart';

const _fileName = 'Llama-3.2-1B-Instruct-Q4_K_M.gguf';
const _url =
    'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/'
    '$_fileName';
const _sha256 =
    '6f85a640a97cf2bf5b8e764087b1e83da0fdb51d7c9fab7d0fece9385611df83';

Future<void> main() async {
  final target = File('assets/models/$_fileName');
  if (await target.exists()) {
    stdout.writeln('Checking existing ${target.path} ...');
    if (await _hash(target) == _sha256) {
      stdout.writeln('Model already present and verified.');
      return;
    }
    stdout.writeln('Existing file does not match; downloading again.');
  }

  await target.parent.create(recursive: true);
  final part = File('${target.path}.part');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(_url));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Download failed: HTTP ${response.statusCode}');
    }
    final total = response.contentLength;
    final sink = part.openWrite();
    var received = 0;
    var lastPercent = -1;
    await for (final chunk in response) {
      sink.add(chunk);
      received += chunk.length;
      final percent = total > 0 ? received * 100 ~/ total : -1;
      if (percent != lastPercent) {
        lastPercent = percent;
        stdout.write('\rDownloading $_fileName: $percent%');
      }
    }
    await sink.close();
    stdout.writeln();
  } finally {
    client.close();
  }

  if (await _hash(part) != _sha256) {
    await part.delete();
    stderr.writeln('Checksum mismatch; the download was discarded.');
    exitCode = 1;
    return;
  }
  await part.rename(target.path);
  stdout.writeln('Saved ${target.path}');
}

Future<String> _hash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
