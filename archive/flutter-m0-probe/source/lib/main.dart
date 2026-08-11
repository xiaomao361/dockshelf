import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:super_clipboard/super_clipboard.dart' show DataReader;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

void main() {
  runApp(const DockShelfApp());
}

class DockShelfApp extends StatelessWidget {
  const DockShelfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '搁这儿',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff49658f)),
        useMaterial3: true,
      ),
      home: const ShelfProbePage(),
    );
  }
}

class ShelfProbePage extends StatefulWidget {
  const ShelfProbePage({super.key});

  @override
  State<ShelfProbePage> createState() => _ShelfProbePageState();
}

class _ShelfProbePageState extends State<ShelfProbePage> {
  static const maxItems = 20;

  final List<Uri> _items = [];
  Timer? _validityTimer;
  bool _isDragOver = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _validityTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _items.isNotEmpty) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _validityTimer?.cancel();
    super.dispose();
  }

  DropOperation _onDropOver(DropOverEvent event) {
    final acceptsFiles = event.session.items.any(
      (item) => item.canProvide(Formats.fileUri),
    );
    if (acceptsFiles && !_isDragOver) {
      setState(() => _isDragOver = true);
    }
    return acceptsFiles ? DropOperation.copy : DropOperation.none;
  }

  Future<void> _onPerformDrop(PerformDropEvent event) async {
    final droppedUris = <Uri>[];
    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null || !reader.canProvide(Formats.fileUri)) {
        continue;
      }
      final uri = await _readFileUri(reader);
      if (uri != null && uri.isScheme('file')) {
        droppedUris.add(uri);
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isDragOver = false;
      var added = 0;
      for (final uri in droppedUris) {
        if (_items.length >= maxItems) {
          break;
        }
        if (!_items.contains(uri)) {
          _items.add(uri);
          added += 1;
        }
      }
      _message = _items.length >= maxItems && droppedUris.length > added
          ? '已达 $maxItems 项上限，多余文件未加入。'
          : added == 0
          ? '没有可添加的新文件。'
          : '已加入 $added 项。';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搁这儿 · 拖放探针'),
        actions: [
          if (_items.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                _items.clear();
                _message = '已清空当前会话。';
              }),
              child: const Text('清空'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: DropRegion(
        formats: const [Formats.fileUri],
        hitTestBehavior: HitTestBehavior.opaque,
        onDropOver: _onDropOver,
        onDropEnter: (_) => setState(() => _isDragOver = true),
        onDropLeave: (_) => setState(() => _isDragOver = false),
        onPerformDrop: _onPerformDrop,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: _isDragOver
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isDragOver ? '松手放到搁板' : '从 Finder 拖文件到这里',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text('仅保存文件引用，不复制内容 · ${_items.length}/$maxItems'),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!, key: const Key('status-message')),
              ],
              const SizedBox(height: 20),
              Expanded(
                child: _items.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无文件\n拖入后，可从文件卡片再拖回 Finder、浏览器或聊天工具。',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _FileReferenceTile(
                          uri: _items[index],
                          onRemove: () => setState(() {
                            _items.removeAt(index);
                            _message = null;
                          }),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<Uri?> _readFileUri(DataReader reader) {
  final completer = Completer<Uri?>();
  final progress = reader.getValue<Uri>(
    Formats.fileUri,
    (value) {
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    },
    onError: (error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    },
  );
  if (progress == null && !completer.isCompleted) {
    completer.complete(null);
  }
  return completer.future;
}

class _FileReferenceTile extends StatelessWidget {
  const _FileReferenceTile({required this.uri, required this.onRemove});

  final Uri uri;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final path = uri.toFilePath();
    final exists =
        FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
    final name = path.split(Platform.pathSeparator).last;

    return DragItemWidget(
      dragItemProvider: (_) async {
        if (!exists) {
          return null;
        }
        final item = DragItem(localData: uri);
        item.add(Formats.fileUri(uri));
        return item;
      },
      allowedOperations: () => const [DropOperation.copy],
      child: DraggableWidget(
        child: Card(
          color: exists
              ? Theme.of(context).colorScheme.surfaceContainerLow
              : Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            leading: Icon(
              exists ? Icons.insert_drive_file_outlined : Icons.link_off,
            ),
            title: Text(name.isEmpty ? path : name),
            subtitle: Text(exists ? path : '原文件已失效\n$path'),
            isThreeLine: !exists,
            trailing: IconButton(
              tooltip: '移除引用',
              onPressed: onRemove,
              icon: const Icon(Icons.close),
            ),
          ),
        ),
      ),
    );
  }
}
