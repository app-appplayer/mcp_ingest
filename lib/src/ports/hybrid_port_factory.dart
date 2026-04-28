/// Hybrid port factory for local/cloud fallback support.
library;

import 'package:mcp_bundle/ports.dart';

export 'package:mcp_bundle/ports.dart' show IngestPorts;

import '../core/exceptions.dart';

/// Processing strategy for selecting between local and cloud services.
enum ProcessingStrategy {
  /// Use only local native plugins (offline, free).
  localOnly,

  /// Use only cloud APIs (online, paid).
  cloudOnly,

  /// Prefer local, fallback to cloud if unavailable.
  localFirst,

  /// Prefer cloud, fallback to local if API fails.
  cloudFirst,
}

/// Factory for creating hybrid ports with local/cloud fallback support.
class HybridPortFactory {
  /// Local native implementations.
  final IngestPorts localPorts;

  /// Cloud API implementations.
  final IngestPorts cloudPorts;

  /// Processing strategy.
  final ProcessingStrategy strategy;

  HybridPortFactory({
    required this.localPorts,
    required this.cloudPorts,
    this.strategy = ProcessingStrategy.localFirst,
  });

  /// Create OcrPort with fallback support.
  OcrPort? createOcrPort() {
    final local = localPorts.ocr;
    final cloud = cloudPorts.ocr;

    if (local == null && cloud == null) return null;

    return HybridOcrPort(
      local: local,
      cloud: cloud,
      strategy: strategy,
    );
  }

  /// Create AsrPort with fallback support.
  AsrPort? createAsrPort() {
    final local = localPorts.asr;
    final cloud = cloudPorts.asr;

    if (local == null && cloud == null) return null;

    return HybridAsrPort(
      local: local,
      cloud: cloud,
      strategy: strategy,
    );
  }

  /// Create all ports with fallback support.
  IngestPorts createPorts() {
    return IngestPorts(
      ocr: createOcrPort(),
      asr: createAsrPort(),
      vision: cloudPorts.vision ?? localPorts.vision,
      storage: localPorts.storage ?? cloudPorts.storage,
    );
  }
}

/// Hybrid OCR port with fallback support.
class HybridOcrPort implements OcrPort {
  final OcrPort? local;
  final OcrPort? cloud;
  final ProcessingStrategy strategy;

  HybridOcrPort({
    this.local,
    this.cloud,
    required this.strategy,
  });

  @override
  Future<OcrResult> recognize(
    Stream<List<int>> imageData,
    OcrOptions options,
  ) async {
    switch (strategy) {
      case ProcessingStrategy.localOnly:
        if (local == null) {
          throw PortNotConfiguredException('LocalOcrPort');
        }
        return local!.recognize(imageData, options);

      case ProcessingStrategy.cloudOnly:
        if (cloud == null) {
          throw PortNotConfiguredException('CloudOcrPort');
        }
        return cloud!.recognize(imageData, options);

      case ProcessingStrategy.localFirst:
        if (local != null && await local!.isAvailable()) {
          try {
            return await local!.recognize(imageData, options);
          } catch (e) {
            if (cloud != null) {
              return cloud!.recognize(imageData, options);
            }
            rethrow;
          }
        }
        if (cloud != null) {
          return cloud!.recognize(imageData, options);
        }
        throw PortNotConfiguredException('OcrPort');

      case ProcessingStrategy.cloudFirst:
        if (cloud != null) {
          try {
            return await cloud!.recognize(imageData, options);
          } catch (e) {
            if (local != null && await local!.isAvailable()) {
              return local!.recognize(imageData, options);
            }
            rethrow;
          }
        }
        if (local != null && await local!.isAvailable()) {
          return local!.recognize(imageData, options);
        }
        throw PortNotConfiguredException('OcrPort');
    }
  }

  @override
  Future<bool> isAvailable() async {
    switch (strategy) {
      case ProcessingStrategy.localOnly:
        return local != null && await local!.isAvailable();
      case ProcessingStrategy.cloudOnly:
        return cloud != null;
      case ProcessingStrategy.localFirst:
      case ProcessingStrategy.cloudFirst:
        final localAvailable = local != null && await local!.isAvailable();
        final cloudAvailable = cloud != null;
        return localAvailable || cloudAvailable;
    }
  }

  @override
  Future<List<String>> supportedLanguages() async {
    final languages = <String>{};
    if (local != null) {
      languages.addAll(await local!.supportedLanguages());
    }
    if (cloud != null) {
      languages.addAll(await cloud!.supportedLanguages());
    }
    return languages.toList();
  }
}

/// Hybrid ASR port with fallback support.
class HybridAsrPort implements AsrPort {
  final AsrPort? local;
  final AsrPort? cloud;
  final ProcessingStrategy strategy;

  HybridAsrPort({
    this.local,
    this.cloud,
    required this.strategy,
  });

  @override
  Future<AsrResult> transcribe(
    Stream<List<int>> audioData,
    AsrOptions options,
  ) async {
    switch (strategy) {
      case ProcessingStrategy.localOnly:
        if (local == null) {
          throw PortNotConfiguredException('LocalAsrPort');
        }
        return local!.transcribe(audioData, options);

      case ProcessingStrategy.cloudOnly:
        if (cloud == null) {
          throw PortNotConfiguredException('CloudAsrPort');
        }
        return cloud!.transcribe(audioData, options);

      case ProcessingStrategy.localFirst:
        if (local != null && await local!.isAvailable()) {
          try {
            return await local!.transcribe(audioData, options);
          } catch (e) {
            if (cloud != null) {
              return cloud!.transcribe(audioData, options);
            }
            rethrow;
          }
        }
        if (cloud != null) {
          return cloud!.transcribe(audioData, options);
        }
        throw PortNotConfiguredException('AsrPort');

      case ProcessingStrategy.cloudFirst:
        if (cloud != null) {
          try {
            return await cloud!.transcribe(audioData, options);
          } catch (e) {
            if (local != null && await local!.isAvailable()) {
              return local!.transcribe(audioData, options);
            }
            rethrow;
          }
        }
        if (local != null && await local!.isAvailable()) {
          return local!.transcribe(audioData, options);
        }
        throw PortNotConfiguredException('AsrPort');
    }
  }

  @override
  Future<bool> isAvailable() async {
    switch (strategy) {
      case ProcessingStrategy.localOnly:
        return local != null && await local!.isAvailable();
      case ProcessingStrategy.cloudOnly:
        return cloud != null;
      case ProcessingStrategy.localFirst:
      case ProcessingStrategy.cloudFirst:
        final localAvailable = local != null && await local!.isAvailable();
        final cloudAvailable = cloud != null;
        return localAvailable || cloudAvailable;
    }
  }

  @override
  Future<List<String>> supportedLanguages() async {
    final languages = <String>{};
    if (local != null) {
      languages.addAll(await local!.supportedLanguages());
    }
    if (cloud != null) {
      languages.addAll(await cloud!.supportedLanguages());
    }
    return languages.toList();
  }
}
