import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'package:open_wearable/widgets/sensors/oe/oe_library_entry.dart';
import 'package:open_wearable/widgets/sensors/oe/oe_library_page.dart';
import 'package:open_wearable/widgets/sensors/oe/oe_library_storage.dart';
import '../../models/oe/oe_fixture.dart';

void main() {
  testWidgets(
      'archive hides a log, retains original and notes, and restores it',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('oe_archive_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      directory.deleteSync(recursive: true);
    });
    final bytes = oeFixture();
    final recording = OeRecording.parse(bytes);
    final entry = OeLibraryEntry(
      'pair.oe',
      recording.digest,
      bytes.length,
      timestampUs: recording.timestampUs,
      side: recording.side,
      deviceId: recording.deviceId,
    );
    await tester.runAsync(() async {
      await saveOeOriginal(entry, bytes);
      await saveOeAnnotations(entry.digest, {'notes': 'retain me'});
    });
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> finishIo() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
    }

    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: OeLibraryPage()));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await finishIo();
    expect(
      find.text('pair.oe'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.runAsync(() => tester.tap(find.text('Archive selected')));
    await finishIo();
    expect(find.text('pair.oe'), findsNothing);
    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();
    expect(find.text('pair.oe'), findsOneWidget);
    await tester.runAsync(() async {
      expect(await readOeOriginal(entry), orderedEquals(bytes));
      expect(
        await readOeAnnotations(entry.digest),
        {'notes': 'retain me', 'archived': 'true'},
      );
    });
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.runAsync(() => tester.tap(find.text('Restore selected')));
    await finishIo();
    expect(find.text('pair.oe'), findsNothing);
    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle();
    expect(find.text('pair.oe'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    for (final mode in ['Tiles', 'Table', 'List']) {
      await tester.tap(find.text(mode));
      await tester.pumpAndSettle();
      expect(find.text('pair.oe'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      expect(find.text('Compare selected logs (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    final previousPicker = FilePickerPlatform.instance;
    addTearDown(() => FilePickerPlatform.instance = previousPicker);
    final second = oeFixture();
    ByteData.sublistView(second).setUint64(18, 2, Endian.little);
    final third = oeFixture();
    ByteData.sublistView(third).setUint64(18, 3, Endian.little);
    FilePickerPlatform.instance = _BatchPicker([
      _PickedFile('duplicate.oe', bytes),
      _PickedFile('second.oe', second),
      _PickedFile('broken.oe', Uint8List.fromList([0, 0])),
      _PickedFile('third.oe', third),
    ]);
    await tester.runAsync(() async {
      await tester.tap(find.text('Import .oe files'));
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pumpAndSettle();
    expect(
      find.text('2 imported · 1 already in library · 1 failed'),
      findsOneWidget,
    );
    expect(find.text('second.oe'), findsOneWidget);
    expect(find.text('third.oe'), findsOneWidget);
    expect(find.text('pair.oe'), findsOneWidget);
    expect(find.textContaining('broken.oe:'), findsOneWidget);
    await tester.runAsync(() async {
      final entries = await listOeOriginals();
      expect(entries.length, 3);
      final batch = entries.where((e) => e.name != 'pair.oe').toList();
      expect(batch[0].sessionId, isNotNull);
      expect(batch[0].sessionId, batch[1].sessionId);
      expect(batch[0].importedAtUs, batch[1].importedAtUs);
      expect(entries.singleWhere((e) => e.name == 'pair.oe').sessionId, isNull);
      expect((await readOeAnnotations(entry.digest))['notes'], 'retain me');
    });
    expect(tester.takeException(), isNull);
    final sessionTitle = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .singleWhere((s) => s.startsWith('Import ') && !s.contains('.oe'));
    await tester.tap(find.text(sessionTitle));
    await tester.pumpAndSettle();
    expect(find.text('second.oe'), findsNothing);
    expect(find.text('pair.oe'), findsOneWidget);
    await tester.tap(find.text(sessionTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select session').first);
    await tester.pump();
    expect(find.text('Compare selected logs (2)'), findsOneWidget);
    await tester
        .runAsync(() => tester.tap(find.byTooltip('Rename session').first));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Session name'),
      'Reading practice',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();
    expect(find.text('Reading practice'), findsOneWidget);
    await tester.runAsync(() async {
      for (final entry
          in (await listOeOriginals()).where((e) => e.sessionId != null)) {
        expect(
          (await readOeAnnotations(entry.digest))['session_name'],
          'Reading practice',
        );
      }
    });
    await tester.runAsync(() => tester.tap(find.text('Merge sessions')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Merge'))
            .onPressed,
        isNull,);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Reading practice'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Earlier imports'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Combined session name'),
        'All readings',);
    await tester.runAsync(() async {
      await tester.tap(find.text('Merge'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();
    expect(find.text('All readings'), findsOneWidget);
    expect(find.text('Reading practice'), findsNothing);
    expect(find.text('Earlier imports'), findsNothing);
    await tester.runAsync(() async {
      final ids = <String>{};
      for (final entry in await listOeOriginals()) {
        final notes = await readOeAnnotations(entry.digest);
        ids.add(notes['session_id']!);
        expect(notes['session_name'], 'All readings');
        await readOeOriginal(entry);
      }
      expect(ids.length, 1);
      expect((await readOeAnnotations(entry.digest))['notes'], 'retain me');
    });
    expect(tester.takeException(), isNull);
  });
}

final class _PickedFile extends PlatformFile {
  _PickedFile(this.name, this.bytes);
  @override
  final String name;
  final Uint8List bytes;
  @override
  Uri get uri => Uri.parse('memory:$name');
  @override
  Never get xFile => throw UnsupportedError('Not used');
  @override
  int? lengthSync() => bytes.length;
  @override
  Future<int?> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

class _BatchPicker extends FilePickerPlatform {
  _BatchPicker(this.files);
  final List<PlatformFile> files;
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async =>
      files;
}
