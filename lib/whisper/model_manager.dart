import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

class WhisperModelManager {
  static final _log = Logger('WhisperModelManager');
  static const _modelUrl = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin';
  static const _modelFileName = 'whisper-base.bin';
  
  /// Downloads and prepares the Whisper model
  static Future<String> prepareModel() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/$_modelFileName';

      // Check if model already exists
      if (await File(modelPath).exists()) {
        _log.info('Whisper model already exists at: $modelPath');
        return modelPath;
      }

      // Try to load from assets first
      try {
        final byteData = await rootBundle.load('assets/$_modelFileName');
        final buffer = byteData.buffer;
        await File(modelPath).writeAsBytes(
          buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes)
        );
        _log.info('Whisper model copied from assets to: $modelPath');
        return modelPath;
      } catch (e) {
        _log.info('Model not found in assets, downloading from HuggingFace...');
      }

      // Download model from HuggingFace
      final response = await http.get(Uri.parse(_modelUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download model: ${response.statusCode}');
      }

      // Save model to local storage
      await File(modelPath).writeAsBytes(response.bodyBytes);
      _log.info('Whisper model downloaded and saved to: $modelPath');
      
      return modelPath;
    } catch (e) {
      _log.severe('Error preparing Whisper model: $e');
      rethrow;
    }
  }

  /// Validates the model file
  static Future<bool> validateModel(String modelPath) async {
    try {
      final file = File(modelPath);
      if (!await file.exists()) {
        return false;
      }

      // Check file size (base model should be ~140MB)
      final size = await file.length();
      if (size < 140000000) {
        _log.warning('Model file seems too small: $size bytes');
        return false;
      }

      return true;
    } catch (e) {
      _log.severe('Error validating model: $e');
      return false;
    }
  }
}