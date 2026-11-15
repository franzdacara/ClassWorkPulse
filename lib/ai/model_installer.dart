import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Thrown when the app was built without a GGUF file in `assets/models/`.
class ModelNotBundledException implements Exception {
  const ModelNotBundledException();

  @override
  String toString() => 'No GGUF model is bundled with this build.';
}

/// Makes the GGUF model that ships inside the app available as a real file,
/// which is what llama.cpp needs to load it.
abstract final class ModelInstaller {
  static const MethodChannel _channel = MethodChannel('classwork_pulse/model');
  static const String _assetDir = 'assets/models/';

  /// Asset key of the bundled model, or null if the build has none.
  static Future<String?> bundledModelAsset() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final models =
        manifest
            .listAssets()
            .where(
              (key) =>
                  key.startsWith(_assetDir) &&
                  key.toLowerCase().endsWith('.gguf'),
            )
            .toList()
          ..sort();
    return models.isEmpty ? null : models.first;
  }

  /// Returns the file path of the model, copying it out of the app package
  /// first if the platform requires that.
  ///
  /// [onProgress] receives the copied fraction (null when unknown).
  static Future<String> ensureInstalled({
    void Function(double? fraction)? onProgress,
  }) async {
    final asset = await bundledModelAsset();
    if (asset == null) throw const ModelNotBundledException();

    if (Platform.isAndroid) return _installOnAndroid(asset, onProgress);
    if (Platform.isIOS) return _locateOnIos(asset);
    throw UnsupportedError(
      'The on-device assistant is available on Android and iOS only.',
    );
  }

  /// Android keeps assets inside the APK, so the model is streamed out to app
  /// storage once (natively, to avoid holding the whole file in memory).
  static Future<String> _installOnAndroid(
    String asset,
    void Function(double? fraction)? onProgress,
  ) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'models'));
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, p.basename(asset)));

    final bundledLength =
        await _channel.invokeMethod<int>('assetLength', {'asset': asset}) ?? -1;
    if (await target.exists() &&
        (bundledLength < 0 || await target.length() == bundledLength)) {
      return target.path;
    }

    // Clear partial copies and models left by an earlier app version before
    // copying, so they do not take up space the new copy needs.
    await for (final entity in dir.list()) {
      if (entity is File) await entity.delete();
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'copyProgress') return;
      final args = call.arguments as Map<Object?, Object?>;
      final copied = (args['copied'] as num).toDouble();
      final total = (args['total'] as num).toDouble();
      onProgress?.call(total > 0 ? (copied / total).clamp(0.0, 1.0) : null);
    });
    try {
      await _channel.invokeMethod<void>('copyAsset', {
        'asset': asset,
        'dest': target.path,
      });
    } finally {
      _channel.setMethodCallHandler(null);
    }
    return target.path;
  }

  /// iOS stores Flutter assets as plain files in the app bundle, so the model
  /// is loaded in place without a second copy.
  static Future<String> _locateOnIos(String asset) async {
    final path = p.joinAll([
      p.dirname(Platform.resolvedExecutable),
      'Frameworks',
      'App.framework',
      'flutter_assets',
      ...asset.split('/'),
    ]);
    if (!await File(path).exists()) {
      throw StateError('The bundled model was not found at $path');
    }
    return path;
  }
}
