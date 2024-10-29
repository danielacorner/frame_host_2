import 'dart:async';
import 'dart:typed_data';

import 'package:buffered_list_stream/buffered_list_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_whisper/flutter_whisper.dart';
import 'package:logging/logging.dart';
import 'package:record/record.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/text_utils.dart';
import 'package:simple_frame_app/tx/plain_text.dart';
import 'package:frame_flutter_translate_host/whisper/model_manager.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {
  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  /// Whisper model configuration
  late final FlutterWhisper _whisper;
  static const _sampleRate = 16000;
  String? _modelError;

  String _text = "N/A";
  String _translatedText = "N/A";

  @override
  void initState() {
    super.initState();
    currentState = ApplicationState.initializing;
    // Initialize Whisper
    _initWhisper();
  }

  @override
  void dispose() async {
    await _whisper.dispose();
    super.dispose();
  }

  void _initWhisper() async {
    try {
      _whisper = FlutterWhisper();
      
      // Prepare the model
      final modelPath = await WhisperModelManager.prepareModel();
      
      // Validate the model
      if (!await WhisperModelManager.validateModel(modelPath)) {
        throw Exception('Invalid or corrupted model file');
      }

      // Load the model
      await _whisper.loadModel(
        path: modelPath,
        language: "ko", // Korean language
        translateToEnglish: true, // Enable direct translation to English
      );

      currentState = ApplicationState.disconnected;
    } catch (e) {
      _log.severe('Failed to initialize Whisper: $e');
      _modelError = e.toString();
      currentState = ApplicationState.error;
    } finally {
      if (mounted) setState(() {});
    }
  }

  /// Sets up the Audio used for the application.
  /// Returns true if the audio is set up correctly, in which case
  /// it also returns a reference to the AudioRecorder and the
  /// audioSampleBufferedStream
  Future<(bool, AudioRecorder?, Stream<List<int>>?)> startAudio() async {
    AudioRecorder audioRecorder = AudioRecorder();

    if (!await audioRecorder.hasPermission()) {
      return (false, null, null);
    }

    try {
      final recordStream = await audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          numChannels: 1,
          sampleRate: _sampleRate));

      final audioSampleBufferedStream = bufferedListStream(
        recordStream.map((event) => event.toList()),
        4096 * 2,
      );

      return (true, audioRecorder, audioSampleBufferedStream);
    } catch (e) {
      _log.severe('Error starting Audio: $e');
      return (false, null, null);
    }
  }

  Future<void> stopAudio(AudioRecorder recorder) async {
    await recorder.stop();
    await recorder.dispose();
  }

  @override
  Future<void> run() async {
    if (_modelError != null) {
      _log.severe('Cannot run with model error: $_modelError');
      return;
    }

    currentState = ApplicationState.running;
    _text = '';
    _translatedText = '';
    if (mounted) setState(() {});

    try {
      var (ok, audioRecorder, audioSampleBufferedStream) = await startAudio();
      if (!ok) {
        currentState = ApplicationState.ready;
        if (mounted) setState(() {});
        return;
      }

      String prevText = '';

      await for (var audioSample in audioSampleBufferedStream!) {
        if (currentState != ApplicationState.running) {
          break;
        }

        // Process audio with Whisper
        final result = await _whisper.processAudio(
          Uint8List.fromList(audioSample),
          sampleRate: _sampleRate,
        );

        if (result != null) {
          _text = result.text;
          _translatedText = result.translation ?? _text;

          if (_translatedText == prevText) {
            continue;
          } else if (_translatedText.isEmpty) {
            await frame!.sendMessage(TxPlainText(msgCode: 0x0b, text: ' '));
            prevText = '';
            continue;
          }

          if (_log.isLoggable(Level.FINE)) {
            _log.fine('Translated text: $_translatedText');
          }

          // Send current text to Frame
          String wrappedText = TextUtils.wrapText(_translatedText, 640, 4);
          await frame!.sendMessage(TxPlainText(msgCode: 0x0b, text: wrappedText));

          if (mounted) setState(() {});
          prevText = _translatedText;
        }
      }

      await stopAudio(audioRecorder!);

    } catch (e) {
      _log.severe('Error executing application logic: $e');
    }

    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Future<void> cancel() async {
    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_modelError != null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Error loading model: $_modelError', 
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Translation',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Translation"),
          actions: [getBatteryWidget()]
        ),
        body: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_text, style: const TextStyle(fontSize: 30)),
                const Divider(),
                Text(_translatedText, style: const TextStyle(fontSize: 30, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ),
        floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.mic), const Icon(Icons.mic_off)),
        persistentFooterButtons: getFooterButtonsWidget(),
      ),
    );
  }
}