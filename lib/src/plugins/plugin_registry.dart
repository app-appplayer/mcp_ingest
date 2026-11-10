/// Plugin registry for managing native plugins.
library;

import 'plugin.dart';
import 'pdfium_pdf_plugin.dart';

// Re-export the canonical PluginNotAvailableException from core/exceptions.dart
// so existing consumers that import this file (via barrel with prior `hide`
// still in place for the old local class) can migrate without breaking.
export '../core/exceptions.dart' show PluginNotAvailableException;

/// Manages native plugin registration and selection.
///
/// Provides a centralized registry for OCR, ASR, and PDF plugins.
/// Supports multiple implementations with priority-based selection.
class PluginRegistry {
  final Map<Type, List<NativePlugin>> _plugins = {};
  final Map<String, NativePlugin> _pluginsById = {};

  /// Register a plugin.
  void register<T extends NativePlugin>(T plugin) {
    _plugins.putIfAbsent(T, () => []).add(plugin);
    _pluginsById[plugin.id] = plugin;
  }

  /// Unregister a plugin by ID.
  void unregister(String pluginId) {
    final plugin = _pluginsById.remove(pluginId);
    if (plugin != null) {
      for (final list in _plugins.values) {
        list.remove(plugin);
      }
    }
  }

  /// Get preferred plugin of type.
  ///
  /// Returns the first registered plugin of the given type,
  /// or null if none are registered.
  T? getPlugin<T extends NativePlugin>() {
    final plugins = _plugins[T];
    if (plugins == null || plugins.isEmpty) return null;
    return plugins.first as T;
  }

  /// Get plugin by ID.
  T? getPluginById<T extends NativePlugin>(String id) {
    final plugin = _pluginsById[id];
    if (plugin is T) return plugin;
    return null;
  }

  /// Get all plugins of type.
  List<T> getAllPlugins<T extends NativePlugin>() {
    return (_plugins[T] ?? []).cast<T>();
  }

  /// Get first available plugin of type.
  ///
  /// Checks availability of each plugin and returns the first
  /// one that is available on the current platform.
  Future<T?> getAvailablePlugin<T extends NativePlugin>() async {
    final plugins = _plugins[T];
    if (plugins == null || plugins.isEmpty) return null;

    for (final plugin in plugins) {
      if (await plugin.isAvailable()) {
        return plugin as T;
      }
    }
    return null;
  }

  /// Check if any plugin of type is available.
  Future<bool> hasAvailablePlugin<T extends NativePlugin>() async {
    return await getAvailablePlugin<T>() != null;
  }

  /// Initialize all registered plugins.
  Future<void> initializeAll() async {
    for (final list in _plugins.values) {
      for (final plugin in list) {
        if (await plugin.isAvailable()) {
          await plugin.initialize();
        }
      }
    }
  }

  /// Dispose all registered plugins.
  Future<void> disposeAll() async {
    for (final list in _plugins.values) {
      for (final plugin in list) {
        await plugin.dispose();
      }
    }
    _plugins.clear();
    _pluginsById.clear();
  }

  /// Get registered plugin IDs.
  List<String> get registeredPluginIds => _pluginsById.keys.toList();

  /// Get plugin availability status.
  Future<Map<String, bool>> getAvailabilityStatus() async {
    final status = <String, bool>{};
    for (final entry in _pluginsById.entries) {
      status[entry.key] = await entry.value.isAvailable();
    }
    return status;
  }

  /// Create empty registry.
  PluginRegistry();

  /// Create registry with default PDF plugin.
  ///
  /// Note: OCR and ASR ports are registered separately via
  /// TesseractOcrPlugin and WhisperAsrPlugin which implement
  /// the port interfaces directly.
  factory PluginRegistry.defaults() {
    final registry = PluginRegistry();
    registry.register<PdfPlugin>(PdfiumPdfPlugin());
    return registry;
  }
}
