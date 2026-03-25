import "dart:convert";
import "dart:io";
import "dart:math";

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "src/native/router_core.dart";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RouterCncApp());
}

class RouterCncApp extends StatelessWidget {
  const RouterCncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Router CNC",
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF070D16),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF15B9FF),
          secondary: Color(0xFF7EE3FF),
          surface: Color(0xFF162235),
          surfaceContainerHighest: Color(0xFF1A2940),
        ),
        fontFamily: "Segoe UI",
      ),
      home: const RouterCncHomePage(),
    );
  }
}

class RouterCncHomePage extends StatefulWidget {
  const RouterCncHomePage({
    super.key,
    this.initialStock = const <StockPiece>[],
  });

  final List<StockPiece> initialStock;

  @override
  State<RouterCncHomePage> createState() => _RouterCncHomePageState();
}

class _RouterCncHomePageState extends State<RouterCncHomePage> {
  static const _defaultYaw3d = -0.82;
  static const _defaultPitch3d = -0.26;
  static const _toolbarButtons = <String>[
    "Importar DXF(s)",
    "Importar STEP(s)",
    "Enquadrar (Fit)",
    "Limpar",
    "Nova chapa",
    "Editar chapa",
    "Editar corte",
    "Simular corte",
  ];

  final _searchController = TextEditingController();
  final _sheets = <SheetModel>[];
  final _stock = <StockPiece>[];

  int _nextSheetId = 1;
  int _nextStockId = 1;
  int _activeSheetIndex = 0;

  bool _is2d = true;
  String _stockTypeFilter = "Todos";
  String _coreVersion = "router_core(carregando...)";
  String _status = "Pronto";

  double _lastOperationMs = 0;
  int? _selectedPieceId;

  double _zoom2d = 1;
  Offset _pan2d = Offset.zero;
  double _zoom3d = 1;
  Offset _pan3d = Offset.zero;
  double _yaw3d = _defaultYaw3d;
  double _pitch3d = _defaultPitch3d;

  @override
  void initState() {
    super.initState();
    _sheets.add(SheetModel.defaultSheet(_nextSheetId++));
    for (final item in widget.initialStock) {
      _stock.add(item.copyWith(id: _nextStockId++));
    }
    _loadNativeCoreVersion();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  SheetModel get _activeSheet => _sheets[_activeSheetIndex];

  List<StockPiece> get _filteredStock {
    final query = _searchController.text.trim().toLowerCase();
    final selectedFilter = _stockTypeFilter;
    final out = _stock.where((item) {
      final matchQuery =
          query.isEmpty || item.code.toLowerCase().contains(query);
      final matchType =
          selectedFilter == "Todos" || item.type.label == selectedFilter;
      return matchQuery && matchType;
    }).toList();
    out.sort((a, b) => a.code.toLowerCase().compareTo(b.code.toLowerCase()));
    return out;
  }

  void _loadNativeCoreVersion() {
    final native = RouterCoreNative.tryInstance();
    final version = native?.coreVersion() ?? RouterCoreFallback.coreVersion();
    final loadError = RouterCoreNative.describeLoadError();
    setState(() {
      _coreVersion = loadError.isNotEmpty ? "$version | sem DLL" : version;
      if (loadError.isNotEmpty) _status = loadError;
    });
  }

  void _setStatus(String message) {
    setState(() => _status = message);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _onToolbarAction(String label) {
    switch (label) {
      case "Importar DXF(s)":
        _importFiles(PieceType.dxf);
        return;
      case "Importar STEP(s)":
        _importFiles(PieceType.step);
        return;
      case "Enquadrar (Fit)":
        _resetView();
        return;
      case "Limpar":
        _clearAll();
        return;
      case "Nova chapa":
        _newSheet();
        return;
      case "Editar chapa":
        _editSheetDialog();
        return;
      case "Editar corte":
        _simpleInfoDialog(
          title: "Editar corte",
          body:
              "Painel de corte pronto para evolucao. Nesta versao, os botoes e fluxo estao ativos.",
        );
        return;
      case "Simular corte":
        _simulationDialog();
        return;
      default:
        _setStatus("Acao nao mapeada: $label");
    }
  }

  void _resetView() {
    setState(() {
      if (_is2d) {
        _zoom2d = 1;
        _pan2d = Offset.zero;
      } else {
        _zoom3d = 1;
        _pan3d = Offset.zero;
        _yaw3d = _defaultYaw3d;
        _pitch3d = _defaultPitch3d;
      }
    });
    _setStatus("Enquadrado na chapa ativa.");
  }

  void _clearAll() {
    setState(() {
      _stock.clear();
      for (final sheet in _sheets) {
        sheet.clear();
      }
      _selectedPieceId = null;
      _lastOperationMs = 0;
    });
    _setStatus("Projeto limpo.");
  }

  void _newSheet() {
    setState(() {
      _sheets.add(SheetModel.fromTemplate(_nextSheetId++, _activeSheet));
      _activeSheetIndex = _sheets.length - 1;
    });
    _setStatus("Nova chapa criada.");
  }

  void _deleteSelectedPieceOrSheet() {
    if (_selectedPieceId != null) {
      var removedPiece = false;
      setState(() {
        final before = _activeSheet.pieces.length;
        _activeSheet.pieces.removeWhere((item) => item.id == _selectedPieceId);
        removedPiece = _activeSheet.pieces.length < before;
        if (removedPiece) _selectedPieceId = null;
      });
      if (removedPiece) {
        _setStatus("Peca removida da chapa ativa.");
        return;
      }
    }

    if (_sheets.length <= 1) {
      setState(() {
        _activeSheet.clear();
        _selectedPieceId = null;
      });
      _setStatus("Chapa unica limpa.");
      return;
    }

    setState(() {
      _sheets.removeAt(_activeSheetIndex);
      if (_activeSheetIndex >= _sheets.length) {
        _activeSheetIndex = _sheets.length - 1;
      }
      for (var i = 0; i < _sheets.length; i++) {
        _sheets[i].id = i + 1;
      }
      _nextSheetId = _sheets.length + 1;
      _selectedPieceId = null;
    });
    _setStatus("Chapa removida.");
  }

  void _changeStockQuantity(int pieceId, int delta) {
    final index = _stock.indexWhere((item) => item.id == pieceId);
    if (index < 0) return;

    setState(() {
      final item = _stock[index];
      final next = item.quantity + delta;
      if (next <= 0) {
        _stock.removeAt(index);
      } else {
        item.quantity = next;
      }
    });
  }

  Future<void> _importFiles(PieceType forcedType) async {
    final paths = await _pickFilesWindows(forcedType);

    if (paths.isEmpty) {
      _setStatus("Importacao cancelada.");
      return;
    }

    var imported = 0;
    for (final path in paths) {
      final piece = await _pieceFromPath(path, forcedType);
      if (piece == null) continue;

      final idx = _stock.indexWhere((p) => p.mergeKey == piece.mergeKey);
      if (idx >= 0) {
        _stock[idx].quantity += 1;
      } else {
        _stock.add(piece);
      }
      imported += 1;
    }

    if (imported <= 0) {
      _showSnack("Nenhum arquivo valido importado.");
      return;
    }

    setState(() {});
    _setStatus("$imported arquivo(s) importado(s).");
  }

  Future<List<String>> _pickFilesWindows(PieceType type) async {
    if (!Platform.isWindows) {
      _showSnack(
        "Importacao por seletor nativo foi implementada para Windows.",
      );
      return const [];
    }

    final filter = type == PieceType.dxf
        ? "DXF (*.dxf)|*.dxf"
        : "STEP (*.step;*.stp)|*.step;*.stp";

    final script =
        '''
Add-Type -AssemblyName System.Windows.Forms
\$dialog = New-Object System.Windows.Forms.OpenFileDialog
\$dialog.Filter = '$filter'
\$dialog.Multiselect = \$true
\$dialog.Title = 'Selecionar arquivos ${type.label}'
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  @(\$dialog.FileNames) | ConvertTo-Json -Compress | Write-Output
}
''';

    ProcessResult result;
    try {
      result = await Process.run("powershell", [
        "-NoProfile",
        "-Command",
        script,
      ]);
    } catch (e) {
      _showSnack("Falha ao abrir seletor nativo: $e");
      return const [];
    }

    if (result.exitCode != 0) {
      final error = result.stderr.toString().trim();
      if (error.isNotEmpty) {
        _showSnack("Erro no seletor: $error");
      }
      return const [];
    }

    final stdout = result.stdout.toString().trim();
    if (stdout.isEmpty) return const [];

    dynamic decoded;
    try {
      decoded = jsonDecode(stdout);
    } catch (_) {
      return stdout
          .split(RegExp(r"\r?\n"))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    }

    if (decoded is List) {
      return decoded
          .whereType<String>()
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    }
    if (decoded is String && decoded.trim().isNotEmpty) {
      return [decoded.trim()];
    }
    return const [];
  }

  Future<StockPiece?> _pieceFromPath(
    String path,
    PieceType fallbackType,
  ) async {
    final file = File(path);
    if (!file.existsSync()) return null;

    final code = _removeExtension(_basename(path));
    final type = PieceTypeX.fromExtension(_extension(path)) ?? fallbackType;
    DxfGeometry? dxfGeometry;
    Size? parsed;
    Size dims;

    if (type == PieceType.dxf) {
      try {
        final text = await file.readAsString();
        dxfGeometry = parseDxfGeometry(text);
      } catch (_) {
        dxfGeometry = null;
      }
    }

    if (dxfGeometry != null) {
      dims = Size(dxfGeometry.widthMm, dxfGeometry.heightMm);
    } else {
      parsed = _parseDimensionFromText(code);
      dims = parsed ?? await _dimensionFallback(file);
    }

    return StockPiece(
      id: _nextStockId++,
      code: code,
      widthMm: dims.width.round(),
      heightMm: dims.height.round(),
      type: type,
      quantity: 1,
      colorSeed: _stableHash(path),
      sourcePath: path,
      dxfGeometry: dxfGeometry,
    );
  }

  Size? _parseDimensionFromText(String text) {
    final match = RegExp(r"(\d{2,5})\s*[xX]\s*(\d{2,5})").firstMatch(text);
    if (match == null) return null;
    final w = int.tryParse(match.group(1) ?? "");
    final h = int.tryParse(match.group(2) ?? "");
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return Size(w.toDouble(), h.toDouble());
  }

  Future<Size> _dimensionFallback(File file) async {
    int length = 0;
    try {
      length = await file.length();
    } catch (_) {}
    final seed = _stableHash(file.path) ^ length;
    final w = (180 + (seed % 2600)).clamp(120, 3000);
    final h = (80 + ((seed ~/ 11) % 1200)).clamp(70, 1600);
    return Size(w.toDouble(), h.toDouble());
  }

  void _mountCurrentSheet() {
    if (_stock.isEmpty) {
      _showSnack("Nao ha pecas no card da direita.");
      return;
    }

    final sw = Stopwatch()..start();
    var placed = 0;
    var skipped = 0;
    final sorted = _stock.toList()..sort((a, b) => b.area.compareTo(a.area));

    for (final stock in sorted) {
      while (stock.quantity > 0) {
        final placedPiece = _tryPlace(_activeSheet, stock);
        if (placedPiece == null) {
          skipped += stock.quantity;
          break;
        }
        _activeSheet.pieces.add(placedPiece);
        stock.quantity -= 1;
        placed += 1;
      }
    }

    _stock.removeWhere((s) => s.quantity <= 0);
    sw.stop();

    setState(() => _lastOperationMs = sw.elapsedMilliseconds.toDouble());

    if (placed <= 0) {
      _showSnack("Sem espaco para encaixar pecas na chapa ativa.");
      return;
    }

    _setStatus(
      "Chapa ativa: $placed peca(s) adicionadas${skipped > 0 ? ' | sem espaco: $skipped' : ''}.",
    );
  }

  void _mountAllSheets() {
    if (_stock.isEmpty) {
      _showSnack("Nao ha pecas no card da direita.");
      return;
    }

    final sw = Stopwatch()..start();
    var placed = 0;
    var createdSheets = 0;
    var failed = 0;

    final sorted = _stock.toList()..sort((a, b) => b.area.compareTo(a.area));

    for (final stock in sorted) {
      var blocked = false;
      while (stock.quantity > 0 && !blocked) {
        PlacedPiece? out;

        for (final sheet in _sheets) {
          out = _tryPlace(sheet, stock);
          if (out != null) {
            sheet.pieces.add(out);
            stock.quantity -= 1;
            placed += 1;
            break;
          }
        }

        if (out != null) continue;

        final newSheet = SheetModel.fromTemplate(_nextSheetId++, _activeSheet);
        final placedOnNew = _tryPlace(newSheet, stock);
        if (placedOnNew == null) {
          failed += stock.quantity;
          blocked = true;
          continue;
        }

        newSheet.pieces.add(placedOnNew);
        _sheets.add(newSheet);
        stock.quantity -= 1;
        createdSheets += 1;
        placed += 1;
      }
    }

    _stock.removeWhere((s) => s.quantity <= 0);
    sw.stop();

    setState(() {
      _lastOperationMs = sw.elapsedMilliseconds.toDouble();
      _activeSheetIndex = _sheets.length - 1;
    });

    _setStatus(
      "Montar chapas: $placed peca(s) | novas chapas: $createdSheets${failed > 0 ? ' | fora do tamanho: $failed' : ''}.",
    );
  }

  PlacedPiece? _tryPlace(SheetModel sheet, StockPiece stock) {
    if (sheet.acceptedType != null && sheet.acceptedType != stock.type) {
      return null;
    }

    final normal = _candidate(
      sheet,
      stock.widthMm.toDouble(),
      stock.heightMm.toDouble(),
      false,
    );
    final rotated = _candidate(
      sheet,
      stock.heightMm.toDouble(),
      stock.widthMm.toDouble(),
      true,
    );

    _Candidate? chosen;
    if (normal != null && rotated != null) {
      chosen = (normal.y + normal.h) <= (rotated.y + rotated.h)
          ? normal
          : rotated;
    } else {
      chosen = normal ?? rotated;
    }

    if (chosen == null) return null;

    sheet.cursorX = chosen.nextX;
    sheet.cursorY = chosen.nextY;
    sheet.rowH = chosen.nextRowH;
    sheet.acceptedType ??= stock.type;

    return PlacedPiece(
      id: _stableHash("${sheet.id}-${stock.id}-${sheet.pieces.length}"),
      stockId: stock.id,
      code: stock.code,
      widthMm: chosen.w,
      heightMm: chosen.h,
      xMm: chosen.x,
      yMm: chosen.y,
      color: colorFromSeed(stock.colorSeed),
      type: stock.type,
      rotated: chosen.rotated,
      dxfGeometry: stock.dxfGeometry,
    );
  }

  _Candidate? _candidate(SheetModel sheet, double w, double h, bool rotated) {
    final spacing = sheet.spacingMm;
    final maxW = sheet.widthMm - spacing * 2;
    final maxH = sheet.heightMm - spacing * 2;
    if (w > maxW || h > maxH) return null;

    var x = sheet.cursorX;
    var y = sheet.cursorY;
    var rowH = sheet.rowH;

    final right = sheet.widthMm - spacing;
    final bottom = sheet.heightMm - spacing;

    if (x + w > right) {
      x = spacing;
      y += rowH + spacing;
      rowH = 0;
    }

    if (y + h > bottom) return null;

    return _Candidate(
      x: x,
      y: y,
      w: w,
      h: h,
      rotated: rotated,
      nextX: x + w + spacing,
      nextY: y,
      nextRowH: max(rowH, h),
    );
  }

  Future<void> _editSheetDialog() async {
    final sheet = _activeSheet;
    final w = TextEditingController(text: sheet.widthMm.toStringAsFixed(0));
    final h = TextEditingController(text: sheet.heightMm.toStringAsFixed(0));
    final t = TextEditingController(text: sheet.thicknessMm.toStringAsFixed(1));
    final s = TextEditingController(text: sheet.spacingMm.toStringAsFixed(1));
    var applyAllSheets = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF142338),
          title: const Text("Editar chapa ativa"),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  dialogField("Largura (mm)", w),
                  const SizedBox(height: 8),
                  dialogField("Altura (mm)", h),
                  const SizedBox(height: 8),
                  dialogField("Espessura (mm)", t),
                  const SizedBox(height: 8),
                  dialogField("Espacamento (mm)", s),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: applyAllSheets,
                    onChanged: (value) =>
                        setDialogState(() => applyAllSheets = value ?? false),
                    title: const Text("Todas"),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            FilledButton(
              onPressed: () {
                final width = double.tryParse(w.text.replaceAll(",", "."));
                final height = double.tryParse(h.text.replaceAll(",", "."));
                final thickness = double.tryParse(t.text.replaceAll(",", "."));
                final spacing = double.tryParse(s.text.replaceAll(",", "."));

                if (width == null ||
                    height == null ||
                    thickness == null ||
                    spacing == null ||
                    width <= 0 ||
                    height <= 0 ||
                    thickness <= 0 ||
                    spacing < 0) {
                  _showSnack("Valores invalidos.");
                  return;
                }

                setState(() {
                  final targets = applyAllSheets
                      ? _sheets
                      : <SheetModel>[_activeSheet];
                  for (final target in targets) {
                    target.widthMm = width;
                    target.heightMm = height;
                    target.thicknessMm = thickness;
                    target.spacingMm = spacing;
                    target.normalizeCursor();
                  }
                });
                Navigator.pop(context);
                _setStatus(
                  applyAllSheets
                      ? "Configuracao aplicada em todas as chapas."
                      : "Chapa ${_activeSheet.id} atualizada.",
                );
              },
              child: const Text("Aplicar"),
            ),
          ],
        ),
      ),
    );

    w.dispose();
    h.dispose();
    t.dispose();
    s.dispose();
  }

  Future<void> _simpleInfoDialog({
    required String title,
    required String body,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF142338),
        title: Text(title),
        content: Text(body),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _setStatus("$title aberto.");
            },
            child: const Text("Fechar"),
          ),
        ],
      ),
    );
  }

  Future<void> _simulationDialog() async {
    var speed = 1.0;
    var paused = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          backgroundColor: const Color(0xFF142338),
          title: const Text("Simulacao de corte"),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paused
                      ? "Pausado | x${speed.toStringAsFixed(2)}"
                      : "Rodando | x${speed.toStringAsFixed(2)}",
                ),
                const SizedBox(height: 12),
                Slider(
                  value: speed,
                  min: 0.25,
                  max: 50,
                  divisions: 199,
                  label: "x${speed.toStringAsFixed(2)}",
                  onChanged: (value) => setDialog(() => speed = value),
                ),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () =>
                          setDialog(() => speed = max(0.25, speed / 2)),
                      child: const Text("Diminuir"),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () =>
                          setDialog(() => speed = min(50, speed * 2)),
                      child: const Text("Acelerar"),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => setDialog(() => paused = !paused),
                      child: Text(paused ? "Continuar" : "Pausar"),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setDialog(() {
                speed = 1;
                paused = false;
              }),
              child: const Text("Reiniciar"),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _setStatus(
                  "Simulacao configurada em x${speed.toStringAsFixed(2)}.",
                );
              },
              child: const Text("Fechar"),
            ),
          ],
        ),
      ),
    );
  }

  String _sheetSummary(SheetModel sheet) {
    return "Chapa ${sheet.id}: ${sheet.widthMm.toStringAsFixed(0)} x ${sheet.heightMm.toStringAsFixed(0)} mm | Esp: ${sheet.thicknessMm.toStringAsFixed(1)}";
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _activeSheet;
    final filtered = _filteredStock;

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.delete) {
          _deleteSelectedPieceOrSheet();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 6),
              _TopToolbar(
                is2d: _is2d,
                coreVersion: _coreVersion,
                elapsedMs: _lastOperationMs,
                selectedPieceId: _selectedPieceId,
                sheetSummary: _sheetSummary(sheet),
                onToggle2d: (value) => setState(() => _is2d = value),
                onAction: _onToolbarAction,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const leftWidth = 286.0;
                      const rightWidth = 400.0;
                      const minViewport = 760.0;
                      const gap = 8.0;
                      const minContentWidth =
                          leftWidth + gap + minViewport + gap + rightWidth;
                      final contentWidth = max(
                        minContentWidth,
                        constraints.maxWidth,
                      );

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: contentWidth,
                          child: Row(
                            children: [
                              SizedBox(
                                width: leftWidth,
                                child: _SheetsPanel(
                                  sheets: _sheets,
                                  activeSheetIndex: _activeSheetIndex,
                                  onSelectSheet: (index) {
                                    setState(() {
                                      _activeSheetIndex = index;
                                      _selectedPieceId = null;
                                    });
                                    _setStatus(
                                      "Chapa ${_activeSheet.id} ativada.",
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: gap),
                              Expanded(
                                child: _ViewportPanel(
                                  is2d: _is2d,
                                  sheet: sheet,
                                  allSheets: _sheets,
                                  activeSheetIndex: _activeSheetIndex,
                                  pieces: sheet.pieces,
                                  selectedPieceId: _selectedPieceId,
                                  zoom: _is2d ? _zoom2d : _zoom3d,
                                  pan: _is2d ? _pan2d : _pan3d,
                                  yaw: _yaw3d,
                                  pitch: _pitch3d,
                                  status: _status,
                                  onZoom: (value) {
                                    setState(() {
                                      if (_is2d) {
                                        _zoom2d = value.clamp(0.2, 8);
                                      } else {
                                        _zoom3d = value.clamp(0.2, 8);
                                      }
                                    });
                                  },
                                  onPan: (delta) {
                                    setState(() {
                                      if (_is2d) {
                                        _pan2d += delta;
                                      } else {
                                        _pan3d += delta;
                                      }
                                    });
                                  },
                                  onRotate3d: (dyaw, dpitch) {
                                    setState(() {
                                      _yaw3d += dyaw;
                                      _pitch3d = (_pitch3d + dpitch).clamp(
                                        -1.2,
                                        1.2,
                                      );
                                    });
                                  },
                                  onSelectPiece: (id) {
                                    setState(() {
                                      _selectedPieceId = id;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: gap),
                              SizedBox(
                                width: rightWidth,
                                child: _InventoryPanel(
                                  controller: _searchController,
                                  pieces: filtered,
                                  selectedFilter: _stockTypeFilter,
                                  onSearchChanged: (_) => setState(() {}),
                                  onFilterChanged: (value) =>
                                      setState(() => _stockTypeFilter = value),
                                  onApplyCurrent: _mountCurrentSheet,
                                  onApplyAll: _mountAllSheets,
                                  onAddQty: (id) => _changeStockQuantity(id, 1),
                                  onRemoveQty: (id) =>
                                      _changeStockQuantity(id, -1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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

class _TopToolbar extends StatelessWidget {
  const _TopToolbar({
    required this.is2d,
    required this.coreVersion,
    required this.elapsedMs,
    required this.selectedPieceId,
    required this.sheetSummary,
    required this.onToggle2d,
    required this.onAction,
  });

  final bool is2d;
  final String coreVersion;
  final double elapsedMs;
  final int? selectedPieceId;
  final String sheetSummary;
  final ValueChanged<bool> onToggle2d;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B121E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1F304A)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ..._RouterCncHomePageState._toolbarButtons.map(
              (label) => Padding(
                padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                child: _ToolbarButton(
                  label: label,
                  onTap: () => onAction(label),
                ),
              ),
            ),
            const _BadgeChip(label: "2D"),
            Checkbox(
              value: is2d,
              onChanged: (v) => onToggle2d(v ?? false),
              visualDensity: VisualDensity.compact,
            ),
            _BadgeChip(label: sheetSummary),
            _BadgeChip(label: "Tempo: ${elapsedMs.toStringAsFixed(0)} ms"),
            _BadgeChip(label: "Peca sel.: ${selectedPieceId ?? '-'}"),
            _BadgeChip(label: coreVersion, compact: true),
          ],
        ),
      ),
    );
  }
}

class _SheetsPanel extends StatelessWidget {
  const _SheetsPanel({
    required this.sheets,
    required this.activeSheetIndex,
    required this.onSelectSheet,
  });

  final List<SheetModel> sheets;
  final int activeSheetIndex;
  final ValueChanged<int> onSelectSheet;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: panelDecoration(),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Chapas",
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            "Clique para ativar",
            style: TextStyle(color: Color(0xFF9AB6D5), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: sheets.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final sheet = sheets[index];
                final active = index == activeSheetIndex;
                return InkWell(
                  onTap: () => onSelectSheet(index),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF0F3654)
                          : const Color(0xFF1B2740),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: active
                            ? const Color(0xFF14BAFF)
                            : const Color(0xFF3A4E70),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Chapa ${sheet.id}",
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          "${sheet.widthMm.toStringAsFixed(0)} x ${sheet.heightMm.toStringAsFixed(0)} mm",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFD5E5FF),
                          ),
                        ),
                        Text(
                          "Pecas: ${sheet.pieces.length} | Espacamento: ${sheet.spacingMm.toStringAsFixed(1)} mm",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFAAC2E0),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryPanel extends StatelessWidget {
  const _InventoryPanel({
    required this.controller,
    required this.pieces,
    required this.selectedFilter,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.onApplyCurrent,
    required this.onApplyAll,
    required this.onAddQty,
    required this.onRemoveQty,
  });

  final TextEditingController controller;
  final List<StockPiece> pieces;
  final String selectedFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onApplyCurrent;
  final VoidCallback onApplyAll;
  final ValueChanged<int> onAddQty;
  final ValueChanged<int> onRemoveQty;

  @override
  Widget build(BuildContext context) {
    final total = pieces.fold<int>(0, (sum, p) => sum + p.quantity);
    return Container(
      decoration: panelDecoration(),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Pecas importadas",
            style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ModeButton(label: "Chapa", onTap: onApplyCurrent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModeButton(label: "Montar chapas", onTap: onApplyAll),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onSearchChanged,
                  decoration: const InputDecoration(
                    hintText: "Buscar codigo...",
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: DropdownButtonFormField<String>(
                  initialValue: selectedFilter,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: "Todos", child: Text("Todos")),
                    DropdownMenuItem(value: "DXF", child: Text("DXF")),
                    DropdownMenuItem(value: "STEP", child: Text("STEP")),
                  ],
                  onChanged: (v) {
                    if (v != null) onFilterChanged(v);
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "${pieces.length} codigo(s) | $total peca(s)",
            style: const TextStyle(color: Color(0xFF95B8DC), fontSize: 12),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: pieces.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF324867)),
                    ),
                    child: const Text(
                      "Sem pecas importadas.\nUse Importar DXF(s) ou Importar STEP(s).",
                      style: TextStyle(color: Color(0xFF8FAFD1), fontSize: 12),
                    ),
                  )
                : GridView.builder(
                    itemCount: pieces.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.73,
                        ),
                    itemBuilder: (_, index) {
                      final item = pieces[index];
                      return _StockCard(
                        item: item,
                        onAdd: () => onAddQty(item.id),
                        onRemove: () => onRemoveQty(item.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ViewportPanel extends StatelessWidget {
  const _ViewportPanel({
    required this.is2d,
    required this.sheet,
    required this.allSheets,
    required this.activeSheetIndex,
    required this.pieces,
    required this.selectedPieceId,
    required this.zoom,
    required this.pan,
    required this.yaw,
    required this.pitch,
    required this.status,
    required this.onZoom,
    required this.onPan,
    required this.onRotate3d,
    required this.onSelectPiece,
  });

  final bool is2d;
  final SheetModel sheet;
  final List<SheetModel> allSheets;
  final int activeSheetIndex;
  final List<PlacedPiece> pieces;
  final int? selectedPieceId;
  final double zoom;
  final Offset pan;
  final double yaw;
  final double pitch;
  final String status;
  final ValueChanged<double> onZoom;
  final ValueChanged<Offset> onPan;
  final void Function(double dyaw, double dpitch) onRotate3d;
  final ValueChanged<int?> onSelectPiece;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: panelDecoration(),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                const _FpsChip(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Chapa ${sheet.id}: ${sheet.widthMm.toStringAsFixed(0)} x ${sheet.heightMm.toStringAsFixed(0)} mm | Esp: ${sheet.thicknessMm.toStringAsFixed(1)}",
                    style: const TextStyle(
                      color: Color(0xFFB7CCE7),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return Listener(
                  onPointerSignal: (event) {
                    if (event is! PointerScrollEvent) return;
                    final factor = pow(
                      1.0015,
                      -event.scrollDelta.dy,
                    ).toDouble();
                    onZoom((zoom * factor).clamp(0.2, 8));
                  },
                  onPointerMove: (event) {
                    final primary = (event.buttons & kPrimaryMouseButton) != 0;
                    final secondary =
                        (event.buttons & kSecondaryMouseButton) != 0;
                    if (!primary && !secondary) return;

                    if (is2d || secondary) {
                      onPan(event.delta);
                    } else {
                      onRotate3d(event.delta.dx * 0.01, -event.delta.dy * 0.01);
                    }
                  },
                  child: GestureDetector(
                    onTapDown: (details) {
                      if (!is2d) {
                        onSelectPiece(null);
                        return;
                      }
                      final projection = Projection2D.forSheet(
                        size,
                        sheet,
                        zoom,
                        pan,
                      );
                      final world = projection.screenToWorld(
                        details.localPosition,
                      );
                      if (world == null) {
                        onSelectPiece(null);
                        return;
                      }
                      onSelectPiece(findPieceAt(world.dx, world.dy, sheet));
                    },
                    child: ClipRect(
                      child: CustomPaint(
                        painter: ViewportPainter(
                          is2d: is2d,
                          sheet: sheet,
                          allSheets: allSheets,
                          activeSheetIndex: activeSheetIndex,
                          pieces: pieces,
                          selectedPieceId: selectedPieceId,
                          zoom: zoom,
                          pan: pan,
                          yaw: yaw,
                          pitch: pitch,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF253855))),
            ),
            child: Text(
              is2d
                  ? "Mouse: Arraste pan | Scroll zoom | Clique seleciona peca | $status"
                  : "Mouse: Arraste rotaciona | Botao direito arrasta | Scroll zoom | $status",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF89A6C8), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({
    required this.item,
    required this.onAdd,
    required this.onRemove,
  });

  final StockPiece item;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2B42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A4C69)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF355173)),
              color: const Color(0xFF102036),
            ),
            child: CustomPaint(
              painter: StockPreviewPainter(item),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.code,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            "${item.widthMm} x ${item.heightMm} mm",
            style: const TextStyle(fontSize: 12, color: Color(0xFFAEC8EA)),
          ),
          Text(
            ".${item.type.label}",
            style: const TextStyle(fontSize: 12, color: Color(0xFFA4BDE0)),
          ),
          const SizedBox(height: 6),
          const Text(
            "Qtd:",
            style: TextStyle(fontSize: 12, color: Color(0xFFB9D2F5)),
          ),
          Row(
            children: [
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.remove, size: 16),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Container(
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF4A5D7E)),
                    color: const Color(0xFF0E1A2A),
                  ),
                  child: Text(
                    "${item.quantity}",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 16),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ViewportPainter extends CustomPainter {
  ViewportPainter({
    required this.is2d,
    required this.sheet,
    required this.allSheets,
    required this.activeSheetIndex,
    required this.pieces,
    required this.selectedPieceId,
    required this.zoom,
    required this.pan,
    required this.yaw,
    required this.pitch,
  });

  final bool is2d;
  final SheetModel sheet;
  final List<SheetModel> allSheets;
  final int activeSheetIndex;
  final List<PlacedPiece> pieces;
  final int? selectedPieceId;
  final double zoom;
  final Offset pan;
  final double yaw;
  final double pitch;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF03101F),
    );
    is2d ? _draw2d(canvas, size) : _draw3d(canvas, size);
  }

  void _draw2d(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFF17304D);
    final majorGrid = Paint()..color = const Color(0xFF23466C);
    final step = (26.0 * zoom).clamp(14.0, 80.0);
    final sx = pan.dx % step;
    final sy = pan.dy % step;

    var lineIndex = 0;
    for (double x = sx; x <= size.width; x += step) {
      final paint = (lineIndex % 5 == 0) ? majorGrid : grid;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      lineIndex++;
    }
    lineIndex = 0;
    for (double y = sy; y <= size.height; y += step) {
      final paint = (lineIndex % 5 == 0) ? majorGrid : grid;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      lineIndex++;
    }

    final p = Projection2D.forSheet(size, sheet, zoom, pan);
    final corners = [
      p.worldToScreen(-sheet.widthMm / 2, sheet.heightMm / 2),
      p.worldToScreen(sheet.widthMm / 2, sheet.heightMm / 2),
      p.worldToScreen(sheet.widthMm / 2, -sheet.heightMm / 2),
      p.worldToScreen(-sheet.widthMm / 2, -sheet.heightMm / 2),
    ];

    drawPoly(
      canvas,
      corners,
      fill: const Color(0x0822B7FF),
      stroke: const Color(0xFF15D2FF),
      strokeWidth: 2,
    );

    final margin = sheet.spacingMm;
    final innerWidth = sheet.widthMm - margin * 2;
    final innerHeight = sheet.heightMm - margin * 2;
    if (margin > 0 && innerWidth > 4 && innerHeight > 4) {
      final innerCorners = [
        p.worldToScreen(
          -sheet.widthMm / 2 + margin,
          sheet.heightMm / 2 - margin,
        ),
        p.worldToScreen(
          sheet.widthMm / 2 - margin,
          sheet.heightMm / 2 - margin,
        ),
        p.worldToScreen(
          sheet.widthMm / 2 - margin,
          -sheet.heightMm / 2 + margin,
        ),
        p.worldToScreen(
          -sheet.widthMm / 2 + margin,
          -sheet.heightMm / 2 + margin,
        ),
      ];
      drawPoly(
        canvas,
        innerCorners,
        stroke: const Color(0xFF24D36F),
        strokeWidth: 1.1,
      );
    }

    for (final piece in pieces) {
      final rect = pieceRectWorld(piece, sheet);
      final selected = selectedPieceId == piece.id;
      final hasGeometry = piece.dxfGeometry?.polylines.isNotEmpty ?? false;
      if (!hasGeometry) {
        final poly = [
          p.worldToScreen(rect.left, rect.top),
          p.worldToScreen(rect.right, rect.top),
          p.worldToScreen(rect.right, rect.bottom),
          p.worldToScreen(rect.left, rect.bottom),
        ];
        drawPoly(
          canvas,
          poly,
          fill: piece.color.withValues(alpha: 0.25),
          stroke: selected ? const Color(0xFFFFE875) : piece.color,
          strokeWidth: selected ? 2.2 : 1.1,
        );
      }

      _drawPieceGeometry2d(canvas, p, piece, rect, selected);
    }
  }

  void _draw3d(Canvas canvas, Size size) {
    _draw3dGround(canvas, size);

    for (var i = 0; i < allSheets.length; i++) {
      final current = allSheets[i];
      final offsetStep = max(sheet.widthMm, current.widthMm) + 220;
      final sheetOffsetX = (i - activeSheetIndex) * offsetStep;
      final isActive = i == activeSheetIndex;
      final hw = current.widthMm / 2;
      final thicknessDepth = max(0.8, current.thicknessMm);
      const frontZ = 0.0;
      final backZ = thicknessDepth;
      const edgeBlue = Color(0xFF15D2FF);
      final edgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = edgeBlue;
      final frontFace = _projectPolygon3d([
        Vec3(sheetOffsetX - hw, current.heightMm, frontZ),
        Vec3(sheetOffsetX + hw, current.heightMm, frontZ),
        Vec3(sheetOffsetX + hw, 0, frontZ),
        Vec3(sheetOffsetX - hw, 0, frontZ),
      ], size);
      if (frontFace != null) {
        drawPoly(
          canvas,
          frontFace,
          fill: isActive ? const Color(0x0626B8FF) : const Color(0x021B3B5B),
          stroke: edgeBlue,
          strokeWidth: 2,
        );
      }

      final backFace = _projectPolygon3d([
        Vec3(sheetOffsetX - hw, current.heightMm, backZ),
        Vec3(sheetOffsetX + hw, current.heightMm, backZ),
        Vec3(sheetOffsetX + hw, 0, backZ),
        Vec3(sheetOffsetX - hw, 0, backZ),
      ], size);
      if (backFace != null) {
        drawPoly(canvas, backFace, stroke: edgeBlue, strokeWidth: 2);
      }

      _drawLine3d(
        canvas,
        size,
        Vec3(sheetOffsetX - hw, 0, frontZ),
        Vec3(sheetOffsetX - hw, 0, backZ),
        edgePaint,
      );
      _drawLine3d(
        canvas,
        size,
        Vec3(sheetOffsetX + hw, 0, frontZ),
        Vec3(sheetOffsetX + hw, 0, backZ),
        edgePaint,
      );
      _drawLine3d(
        canvas,
        size,
        Vec3(sheetOffsetX - hw, current.heightMm, frontZ),
        Vec3(sheetOffsetX - hw, current.heightMm, backZ),
        edgePaint,
      );
      _drawLine3d(
        canvas,
        size,
        Vec3(sheetOffsetX + hw, current.heightMm, frontZ),
        Vec3(sheetOffsetX + hw, current.heightMm, backZ),
        edgePaint,
      );

      final spacing = current.spacingMm;
      final innerWidth = current.widthMm - spacing * 2;
      final innerHeight = current.heightMm - spacing * 2;
      if (spacing > 0 && innerWidth > 4 && innerHeight > 4) {
        final innerBorder = _projectPolygon3d([
          Vec3(sheetOffsetX - hw + spacing, current.heightMm - spacing, frontZ),
          Vec3(sheetOffsetX + hw - spacing, current.heightMm - spacing, frontZ),
          Vec3(sheetOffsetX + hw - spacing, spacing, frontZ),
          Vec3(sheetOffsetX - hw + spacing, spacing, frontZ),
        ], size);
        if (innerBorder != null) {
          drawPoly(
            canvas,
            innerBorder,
            stroke: isActive
                ? const Color(0xFF24D36F).withValues(alpha: 0.95)
                : const Color(0xFF558D74).withValues(alpha: 0.75),
            strokeWidth: 1.0,
          );
        }
      }

      for (final piece in current.pieces) {
        final rect = _pieceRectWorld3d(piece, current);
        final selected = isActive && selectedPieceId == piece.id;
        const pieceZBias = -0.04;
        final pieceFrontZ = frontZ + pieceZBias;
        final pieceBackZ = backZ + pieceZBias;
        final hasGeometry = piece.dxfGeometry?.polylines.isNotEmpty ?? false;
        if (!hasGeometry) {
          final frontPoly = _projectPolygon3d([
            Vec3(rect.left + sheetOffsetX, rect.bottom, pieceFrontZ),
            Vec3(rect.right + sheetOffsetX, rect.bottom, pieceFrontZ),
            Vec3(rect.right + sheetOffsetX, rect.top, pieceFrontZ),
            Vec3(rect.left + sheetOffsetX, rect.top, pieceFrontZ),
          ], size);
          final backPoly = _projectPolygon3d([
            Vec3(rect.left + sheetOffsetX, rect.bottom, pieceBackZ),
            Vec3(rect.right + sheetOffsetX, rect.bottom, pieceBackZ),
            Vec3(rect.right + sheetOffsetX, rect.top, pieceBackZ),
            Vec3(rect.left + sheetOffsetX, rect.top, pieceBackZ),
          ], size);
          if (frontPoly != null) {
            drawPoly(
              canvas,
              frontPoly,
              fill: piece.color.withValues(alpha: isActive ? 0.24 : 0.16),
              stroke: selected ? const Color(0xFFFFE875) : piece.color,
              strokeWidth: selected ? 2.2 : 1.1,
            );
          }
          if (backPoly != null) {
            drawPoly(
              canvas,
              backPoly,
              stroke: selected
                  ? const Color(0xFFFFE875).withValues(alpha: 0.82)
                  : piece.color.withValues(alpha: 0.82),
              strokeWidth: selected ? 1.7 : 1.0,
            );
          }
          if (frontPoly != null && backPoly != null) {
            final sidePaint = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.9
              ..color = piece.color.withValues(alpha: 0.70);
            final sideCount = min(frontPoly.length, backPoly.length);
            for (var sideIdx = 0; sideIdx < sideCount; sideIdx++) {
              canvas.drawLine(frontPoly[sideIdx], backPoly[sideIdx], sidePaint);
            }
          }
        } else {
          final outer = _outerContour(piece.dxfGeometry!);
          if (outer != null && outer.length >= 3) {
            final contourFront = _projectContourOnPiece(
              outer,
              piece,
              rect,
              sheetOffsetX,
              pieceFrontZ,
              size,
            );
            if (contourFront != null) {
              drawPoly(
                canvas,
                contourFront,
                fill: piece.color.withValues(alpha: isActive ? 0.24 : 0.16),
                stroke: selected ? const Color(0xFFFFE875) : piece.color,
                strokeWidth: selected ? 2.0 : 1.1,
              );
            }

            final contourBack = _projectContourOnPiece(
              outer,
              piece,
              rect,
              sheetOffsetX,
              pieceBackZ,
              size,
            );
            if (contourBack != null) {
              drawPoly(
                canvas,
                contourBack,
                stroke: selected
                    ? const Color(0xFFFFE875).withValues(alpha: 0.82)
                    : piece.color.withValues(alpha: 0.82),
                strokeWidth: selected ? 1.6 : 1.0,
              );
            }

            if (contourFront != null && contourBack != null) {
              final sidePaint = Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 0.9
                ..color = piece.color.withValues(alpha: 0.70);
              final count = min(contourFront.length, contourBack.length);
              for (var pIdx = 0; pIdx < count; pIdx++) {
                canvas.drawLine(
                  contourFront[pIdx],
                  contourBack[pIdx],
                  sidePaint,
                );
              }
            }
          }
        }
        _drawPieceGeometry3d(
          canvas,
          piece,
          rect,
          selected,
          size,
          pieceFrontZ + 0.03,
          sheetOffsetX,
        );
      }
    }
  }

  void _draw3dGround(Canvas canvas, Size size) {
    final minor = Paint()..color = const Color(0xFF16314A);
    final major = Paint()..color = const Color(0xFF244B73);
    const range = 12;
    const step = 220.0;
    for (var i = -range; i <= range; i++) {
      final x = i * step;
      final paint = i % 5 == 0 ? major : minor;
      _drawLine3d(
        canvas,
        size,
        Vec3(x, 0, -range * step),
        Vec3(x, 0, range * step),
        paint,
      );
      _drawLine3d(
        canvas,
        size,
        Vec3(-range * step, 0, i * step),
        Vec3(range * step, 0, i * step),
        paint,
      );
    }
  }

  List<Offset>? _projectPolygon3d(List<Vec3> points, Size size) {
    final out = <Offset>[];
    for (final point in points) {
      final projected = project3dSafe(point, size);
      if (projected == null) return null;
      out.add(projected);
    }
    return out;
  }

  void _drawLine3d(Canvas canvas, Size size, Vec3 a, Vec3 b, Paint paint) {
    final pa = project3dSafe(a, size);
    final pb = project3dSafe(b, size);
    if (pa == null || pb == null) return;
    canvas.drawLine(pa, pb, paint);
  }

  List<Offset>? _projectContourOnPiece(
    List<Offset> contour,
    PlacedPiece piece,
    Rect rect,
    double offsetX,
    double z,
    Size size,
  ) {
    final out = <Offset>[];
    for (final local in contour) {
      final world = _geometryPointToWorld(
        local,
        piece,
        rect,
        piece.dxfGeometry!,
      );
      final projected = project3dSafe(
        Vec3(world.dx + offsetX, world.dy, z),
        size,
      );
      if (projected == null) return null;
      out.add(projected);
    }
    return out;
  }

  Rect _pieceRectWorld3d(PlacedPiece piece, SheetModel current) {
    final left = -current.widthMm / 2 + piece.xMm;
    final topFromTop = piece.yMm;
    final topY = current.heightMm - topFromTop;
    final bottomY = topY - piece.heightMm;
    return Rect.fromLTRB(
      left,
      min(bottomY, topY),
      left + piece.widthMm,
      max(bottomY, topY),
    );
  }

  void _drawPieceGeometry2d(
    Canvas canvas,
    Projection2D projection,
    PlacedPiece piece,
    Rect rect,
    bool selected,
  ) {
    final geo = piece.dxfGeometry;
    if (geo == null || geo.polylines.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 1.5 : 1.0
      ..color = selected ? const Color(0xFFFFF5A2) : piece.color;

    for (final poly in geo.polylines) {
      if (poly.points.length < 2) continue;
      final path = Path();
      for (var i = 0; i < poly.points.length; i++) {
        final world = _geometryPointToWorld(poly.points[i], piece, rect, geo);
        final screen = projection.worldToScreen(world.dx, world.dy);
        if (i == 0) {
          path.moveTo(screen.dx, screen.dy);
        } else {
          path.lineTo(screen.dx, screen.dy);
        }
      }
      if (poly.closed) path.close();
      canvas.drawPath(path, paint);
    }
  }

  void _drawPieceGeometry3d(
    Canvas canvas,
    PlacedPiece piece,
    Rect rect,
    bool selected,
    Size size,
    double z,
    double offsetX,
  ) {
    final geo = piece.dxfGeometry;
    if (geo == null || geo.polylines.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 1.6 : 1.1
      ..color = selected ? const Color(0xFFFFF5A2) : piece.color;

    for (final poly in geo.polylines) {
      if (poly.points.length < 2) continue;
      final path = Path();
      var hasSegment = false;
      for (var i = 0; i < poly.points.length; i++) {
        final world = _geometryPointToWorld(poly.points[i], piece, rect, geo);
        final screen = project3dSafe(
          Vec3(world.dx + offsetX, world.dy, z),
          size,
        );
        if (screen == null) {
          hasSegment = false;
          continue;
        }
        if (!hasSegment) {
          path.moveTo(screen.dx, screen.dy);
          hasSegment = true;
        } else {
          path.lineTo(screen.dx, screen.dy);
        }
      }
      if (!hasSegment) continue;
      if (poly.closed) path.close();
      canvas.drawPath(path, paint);
    }
  }

  Offset _geometryPointToWorld(
    Offset local,
    PlacedPiece piece,
    Rect rect,
    DxfGeometry geo,
  ) {
    final safeW = geo.widthMm <= 0 ? 1.0 : geo.widthMm;
    final safeH = geo.heightMm <= 0 ? 1.0 : geo.heightMm;

    final u = (local.dx / safeW).clamp(0.0, 1.0);
    final v = (local.dy / safeH).clamp(0.0, 1.0);

    final xr = piece.rotated ? v : u;
    final yr = piece.rotated ? (1 - u) : v;

    final worldX = rect.left + xr * rect.width;
    final worldY = rect.top + yr * rect.height;
    return Offset(worldX, worldY);
  }

  List<Offset>? _outerContour(DxfGeometry geo) {
    DxfPolyline? best;
    var bestArea = 0.0;
    for (final poly in geo.polylines) {
      if (!poly.closed || poly.points.length < 3) continue;
      var area = 0.0;
      for (var i = 0; i < poly.points.length; i++) {
        final a = poly.points[i];
        final b = poly.points[(i + 1) % poly.points.length];
        area += a.dx * b.dy - b.dx * a.dy;
      }
      final normalizedArea = area.abs() * 0.5;
      if (normalizedArea > bestArea) {
        bestArea = normalizedArea;
        best = poly;
      }
    }
    if (best != null) return best.points;

    for (final poly in geo.polylines) {
      if (poly.points.length >= 3) return poly.points;
    }
    return null;
  }

  Offset? project3dSafe(Vec3 point, Size size) {
    final cy = cos(yaw);
    final sy = sin(yaw);
    final cp = cos(pitch);
    final sp = sin(pitch);

    final x1 = point.x * cy + point.z * sy;
    final z1 = -point.x * sy + point.z * cy;
    final y1 = point.y;

    final y2 = y1 * cp - z1 * sp;
    final z2 = y1 * sp + z1 * cp;

    final fit = min(
      (size.width * 0.55) / max(200, sheet.widthMm),
      (size.height * 0.6) / max(200, sheet.heightMm),
    );
    final depth = 1900.0;
    final denominator = depth + z2 + 500;
    if (!denominator.isFinite || denominator < 120) return null;
    final persp = (depth / denominator).clamp(0.12, 4.0);
    final s = fit * zoom * persp;
    final center = size.center(Offset.zero) + pan;
    final sx = center.dx + x1 * s;
    final screenY = center.dy - y2 * s;
    if (!sx.isFinite || !screenY.isFinite) return null;
    if (sx.abs() > size.width * 6 || screenY.abs() > size.height * 6) {
      return null;
    }
    return Offset(sx, screenY);
  }

  Offset project3d(Vec3 point, Size size) {
    return project3dSafe(point, size) ?? size.center(Offset.zero);
  }

  @override
  bool shouldRepaint(covariant ViewportPainter old) => true;
}

class StockPreviewPainter extends CustomPainter {
  StockPreviewPainter(this.item);

  final StockPiece item;

  @override
  void paint(Canvas canvas, Size size) {
    final accent = colorFromSeed(item.colorSeed);
    final maxW = size.width - 14;
    final maxH = size.height - 14;
    final scale = min(maxW / item.widthMm, maxH / item.heightMm);
    final w = item.widthMm * scale;
    final h = item.heightMm * scale;
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;

    final rect = Rect.fromLTWH(left, top, w, h);

    final geo = item.dxfGeometry;
    if (geo != null && geo.polylines.isNotEmpty) {
      final geoW = max(1.0, geo.widthMm);
      final geoH = max(1.0, geo.heightMm);
      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = accent;
      for (final poly in geo.polylines) {
        if (poly.points.length < 2) continue;
        final path = Path();
        for (var i = 0; i < poly.points.length; i++) {
          final point = poly.points[i];
          final sx = rect.left + (point.dx / geoW) * rect.width;
          final sy = rect.bottom - (point.dy / geoH) * rect.height;
          if (i == 0) {
            path.moveTo(sx, sy);
          } else {
            path.lineTo(sx, sy);
          }
        }
        if (poly.closed) path.close();
        canvas.drawPath(path, linePaint);
      }
    } else if (item.type == PieceType.step) {
      canvas.drawLine(
        rect.topLeft,
        rect.bottomRight,
        Paint()
          ..color = accent
          ..strokeWidth = 1.1,
      );
      canvas.drawLine(
        rect.topRight,
        rect.bottomLeft,
        Paint()
          ..color = accent
          ..strokeWidth = 1.1,
      );
    } else {
      final holes = 2 + ((item.colorSeed ~/ 5) % 4);
      for (var i = 0; i < holes; i++) {
        final x = rect.left + rect.width * (0.15 + i * 0.16);
        final y = rect.top + rect.height * (0.25 + (i % 2) * 0.35);
        canvas.drawCircle(
          Offset(x.clamp(rect.left + 3, rect.right - 3), y),
          1.5,
          Paint()..color = accent,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant StockPreviewPainter oldDelegate) =>
      oldDelegate.item != item;
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF253247),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF4A5A79)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF202C40),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFF4C5E7C)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF131D2D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3A4F72)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: compact ? const Color(0xFF9BB3D1) : const Color(0xFFD6E7FF),
          fontSize: compact ? 11 : 12,
        ),
      ),
    );
  }
}

class _FpsChip extends StatelessWidget {
  const _FpsChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF041A10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00B85C)),
      ),
      child: const Text(
        "FPS: 165",
        style: TextStyle(
          color: Color(0xFF00FF7A),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class StockPiece {
  StockPiece({
    required this.id,
    required this.code,
    required this.widthMm,
    required this.heightMm,
    required this.type,
    required this.quantity,
    required this.colorSeed,
    required this.sourcePath,
    this.dxfGeometry,
  });

  int id;
  final String code;
  final int widthMm;
  final int heightMm;
  final PieceType type;
  int quantity;
  final int colorSeed;
  final String sourcePath;
  final DxfGeometry? dxfGeometry;

  double get area => widthMm * heightMm.toDouble();
  String get mergeKey =>
      "${type.name}|${code.toLowerCase()}|${widthMm}x$heightMm";

  StockPiece copyWith({int? id}) {
    return StockPiece(
      id: id ?? this.id,
      code: code,
      widthMm: widthMm,
      heightMm: heightMm,
      type: type,
      quantity: quantity,
      colorSeed: colorSeed,
      sourcePath: sourcePath,
      dxfGeometry: dxfGeometry,
    );
  }
}

class PlacedPiece {
  PlacedPiece({
    required this.id,
    required this.stockId,
    required this.code,
    required this.widthMm,
    required this.heightMm,
    required this.xMm,
    required this.yMm,
    required this.color,
    required this.type,
    required this.rotated,
    this.dxfGeometry,
  });

  final int id;
  final int stockId;
  final String code;
  final double widthMm;
  final double heightMm;
  final double xMm;
  final double yMm;
  final Color color;
  final PieceType type;
  final bool rotated;
  final DxfGeometry? dxfGeometry;
}

class SheetModel {
  SheetModel({
    required this.id,
    required this.widthMm,
    required this.heightMm,
    required this.thicknessMm,
    required this.spacingMm,
    required this.pieces,
    required this.cursorX,
    required this.cursorY,
    required this.rowH,
    required this.acceptedType,
  });

  factory SheetModel.defaultSheet(int id) {
    const spacing = 5.0;
    return SheetModel(
      id: id,
      widthMm: 3000,
      heightMm: 1200,
      thicknessMm: 5,
      spacingMm: spacing,
      pieces: <PlacedPiece>[],
      cursorX: spacing,
      cursorY: spacing,
      rowH: 0,
      acceptedType: null,
    );
  }

  factory SheetModel.fromTemplate(int id, SheetModel source) {
    final spacing = source.spacingMm;
    return SheetModel(
      id: id,
      widthMm: source.widthMm,
      heightMm: source.heightMm,
      thicknessMm: source.thicknessMm,
      spacingMm: spacing,
      pieces: <PlacedPiece>[],
      cursorX: spacing,
      cursorY: spacing,
      rowH: 0,
      acceptedType: null,
    );
  }

  int id;
  double widthMm;
  double heightMm;
  double thicknessMm;
  double spacingMm;
  final List<PlacedPiece> pieces;
  double cursorX;
  double cursorY;
  double rowH;
  PieceType? acceptedType;

  void clear() {
    pieces.clear();
    acceptedType = null;
    cursorX = spacingMm;
    cursorY = spacingMm;
    rowH = 0;
  }

  void normalizeCursor() {
    cursorX = cursorX.clamp(spacingMm, max(spacingMm, widthMm - spacingMm));
    cursorY = cursorY.clamp(spacingMm, max(spacingMm, heightMm - spacingMm));
    rowH = rowH.clamp(0, max(0, heightMm - spacingMm));
  }
}

enum PieceType { dxf, step }

extension PieceTypeX on PieceType {
  String get label => this == PieceType.dxf ? "DXF" : "STEP";

  static PieceType? fromExtension(String extLower) {
    if (extLower == "dxf") return PieceType.dxf;
    if (extLower == "step" || extLower == "stp") return PieceType.step;
    return null;
  }
}

class DxfGeometry {
  const DxfGeometry({
    required this.widthMm,
    required this.heightMm,
    required this.polylines,
  });

  final double widthMm;
  final double heightMm;
  final List<DxfPolyline> polylines;
}

class DxfPolyline {
  const DxfPolyline({required this.points, required this.closed});

  final List<Offset> points;
  final bool closed;
}

class _DxfPair {
  const _DxfPair(this.code, this.value);

  final String code;
  final String value;
}

DxfGeometry? parseDxfGeometry(String raw) {
  final cleaned = raw.replaceAll("\r", "");
  final lines = const LineSplitter().convert(cleaned);
  if (lines.length < 4) return null;

  final pairs = <_DxfPair>[];
  for (var i = 0; i + 1 < lines.length; i += 2) {
    pairs.add(_DxfPair(lines[i].trim(), lines[i + 1].trim()));
  }
  if (pairs.isEmpty) return null;

  final polylines = <DxfPolyline>[];
  var currentSection = "";

  for (var i = 0; i < pairs.length; i++) {
    final pair = pairs[i];
    if (pair.code != "0") continue;
    final token = pair.value.toUpperCase();

    if (token == "SECTION") {
      if (i + 1 < pairs.length && pairs[i + 1].code == "2") {
        currentSection = pairs[i + 1].value.toUpperCase();
      }
      continue;
    }
    if (token == "ENDSEC") {
      currentSection = "";
      continue;
    }
    if (currentSection != "ENTITIES") continue;

    if (token == "LINE") {
      final end = _nextEntityIndex(pairs, i + 1);
      final entity = pairs.sublist(i + 1, end);
      final x1 = _readCode(entity, "10");
      final y1 = _readCode(entity, "20");
      final x2 = _readCode(entity, "11");
      final y2 = _readCode(entity, "21");
      if (x1 != null && y1 != null && x2 != null && y2 != null) {
        polylines.add(
          DxfPolyline(points: [Offset(x1, y1), Offset(x2, y2)], closed: false),
        );
      }
      i = end - 1;
      continue;
    }

    if (token == "LWPOLYLINE") {
      final end = _nextEntityIndex(pairs, i + 1);
      final entity = pairs.sublist(i + 1, end);
      final flags = _readCode(entity, "70")?.round() ?? 0;
      final closed = (flags & 1) == 1;

      final points = <Offset>[];
      double? pendingX;
      for (final item in entity) {
        if (item.code == "10") {
          pendingX = _asDouble(item.value);
        } else if (item.code == "20" && pendingX != null) {
          final y = _asDouble(item.value);
          if (y != null) points.add(Offset(pendingX, y));
          pendingX = null;
        }
      }

      if (points.length >= 2) {
        polylines.add(DxfPolyline(points: points, closed: closed));
      }
      i = end - 1;
      continue;
    }

    if (token == "POLYLINE") {
      final headerEnd = _nextEntityIndex(pairs, i + 1);
      final header = pairs.sublist(i + 1, headerEnd);
      final flags = _readCode(header, "70")?.round() ?? 0;
      final closed = (flags & 1) == 1;

      final points = <Offset>[];
      var j = headerEnd;
      while (j < pairs.length) {
        if (pairs[j].code != "0") {
          j++;
          continue;
        }
        final entry = pairs[j].value.toUpperCase();
        if (entry == "VERTEX") {
          final vertexEnd = _nextEntityIndex(pairs, j + 1);
          final vertexData = pairs.sublist(j + 1, vertexEnd);
          final x = _readCode(vertexData, "10");
          final y = _readCode(vertexData, "20");
          if (x != null && y != null) {
            points.add(Offset(x, y));
          }
          j = vertexEnd;
          continue;
        }
        if (entry == "SEQEND") {
          j = _nextEntityIndex(pairs, j + 1);
        }
        break;
      }
      if (points.length >= 2) {
        polylines.add(DxfPolyline(points: points, closed: closed));
      }
      i = j - 1;
      continue;
    }

    if (token == "CIRCLE") {
      final end = _nextEntityIndex(pairs, i + 1);
      final entity = pairs.sublist(i + 1, end);
      final cx = _readCode(entity, "10");
      final cy = _readCode(entity, "20");
      final r = _readCode(entity, "40");
      if (cx != null && cy != null && r != null && r > 0) {
        const segments = 44;
        final points = <Offset>[];
        for (var s = 0; s < segments; s++) {
          final angle = (s / segments) * pi * 2;
          points.add(Offset(cx + cos(angle) * r, cy + sin(angle) * r));
        }
        polylines.add(DxfPolyline(points: points, closed: true));
      }
      i = end - 1;
      continue;
    }

    if (token == "ARC") {
      final end = _nextEntityIndex(pairs, i + 1);
      final entity = pairs.sublist(i + 1, end);
      final cx = _readCode(entity, "10");
      final cy = _readCode(entity, "20");
      final r = _readCode(entity, "40");
      final a0 = _readCode(entity, "50");
      final a1 = _readCode(entity, "51");
      if (cx != null &&
          cy != null &&
          r != null &&
          r > 0 &&
          a0 != null &&
          a1 != null) {
        var start = a0;
        var endAngle = a1;
        if (endAngle < start) endAngle += 360;
        final sweep = (endAngle - start).clamp(0, 360);
        final segments = max(8, (sweep / 7).round());
        final points = <Offset>[];
        for (var s = 0; s <= segments; s++) {
          final t = segments == 0 ? 0 : s / segments;
          final deg = start + sweep * t;
          final rad = deg * (pi / 180);
          points.add(Offset(cx + cos(rad) * r, cy + sin(rad) * r));
        }
        if (points.length >= 2) {
          polylines.add(DxfPolyline(points: points, closed: false));
        }
      }
      i = end - 1;
    }
  }

  if (polylines.isEmpty) return null;

  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final poly in polylines) {
    for (final p in poly.points) {
      minX = min(minX, p.dx);
      minY = min(minY, p.dy);
      maxX = max(maxX, p.dx);
      maxY = max(maxY, p.dy);
    }
  }

  if (!minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite) {
    return null;
  }

  final width = max(1.0, maxX - minX);
  final height = max(1.0, maxY - minY);
  final normalized = polylines
      .map(
        (poly) => DxfPolyline(
          points: poly.points
              .map((p) => Offset(p.dx - minX, p.dy - minY))
              .toList(growable: false),
          closed: poly.closed,
        ),
      )
      .toList(growable: false);

  return DxfGeometry(widthMm: width, heightMm: height, polylines: normalized);
}

int _nextEntityIndex(List<_DxfPair> pairs, int start) {
  var j = start;
  while (j < pairs.length && pairs[j].code != "0") {
    j++;
  }
  return j;
}

double? _readCode(List<_DxfPair> entity, String code) {
  for (final item in entity) {
    if (item.code == code) {
      return _asDouble(item.value);
    }
  }
  return null;
}

double? _asDouble(String text) {
  return double.tryParse(text.replaceAll(",", "."));
}

class _Candidate {
  _Candidate({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.rotated,
    required this.nextX,
    required this.nextY,
    required this.nextRowH,
  });

  final double x;
  final double y;
  final double w;
  final double h;
  final bool rotated;
  final double nextX;
  final double nextY;
  final double nextRowH;
}

class Projection2D {
  Projection2D(this.center, this.scale);

  final Offset center;
  final double scale;

  factory Projection2D.forSheet(
    Size size,
    SheetModel sheet,
    double zoom,
    Offset pan,
  ) {
    final fit = min(
      (size.width * 0.74) / max(200, sheet.widthMm),
      (size.height * 0.70) / max(200, sheet.heightMm),
    );
    return Projection2D(size.center(Offset.zero) + pan, fit * zoom);
  }

  Offset worldToScreen(double wx, double wy) =>
      Offset(center.dx + wx * scale, center.dy - wy * scale);

  Offset? screenToWorld(Offset screen) {
    if (scale.abs() < 0.0001) return null;
    return Offset(
      (screen.dx - center.dx) / scale,
      -(screen.dy - center.dy) / scale,
    );
  }
}

class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

Rect pieceRectWorld(PlacedPiece piece, SheetModel sheet) {
  final left = -sheet.widthMm / 2 + piece.xMm;
  final top = sheet.heightMm / 2 - piece.yMm;
  return Rect.fromLTWH(
    left,
    top - piece.heightMm,
    piece.widthMm,
    piece.heightMm,
  );
}

int? findPieceAt(double worldX, double worldY, SheetModel sheet) {
  for (final piece in sheet.pieces.reversed) {
    final rect = pieceRectWorld(piece, sheet);
    if (rect.contains(Offset(worldX, worldY))) {
      return piece.id;
    }
  }
  return null;
}

void drawPoly(
  Canvas canvas,
  List<Offset> points, {
  Color? fill,
  Color? stroke,
  double strokeWidth = 1,
}) {
  if (points.length < 3) return;
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 1; i < points.length; i++) {
    path.lineTo(points[i].dx, points[i].dy);
  }
  path.close();

  if (fill != null) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = fill,
    );
  }
  if (stroke != null) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = stroke
        ..strokeWidth = strokeWidth,
    );
  }
}

String _basename(String path) {
  final n = path.replaceAll("\\", "/");
  final i = n.lastIndexOf("/");
  return i < 0 ? n : n.substring(i + 1);
}

String _removeExtension(String fileName) {
  final i = fileName.lastIndexOf(".");
  if (i <= 0) return fileName;
  return fileName.substring(0, i);
}

String _extension(String path) {
  final name = _basename(path);
  final i = name.lastIndexOf(".");
  if (i < 0 || i == name.length - 1) return "";
  return name.substring(i + 1).toLowerCase();
}

int _stableHash(String text) {
  var hash = 0;
  for (final ch in text.codeUnits) {
    hash = (hash * 31 + ch) & 0x7fffffff;
  }
  return hash;
}

Color colorFromSeed(int seed) {
  final hue = (seed.abs() % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.78, 0.55).toColor();
}

Widget dialogField(String label, TextEditingController controller) {
  return TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(),
    ),
  );
}

BoxDecoration panelDecoration() {
  return BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF122139), Color(0xFF13233B)],
    ),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: const Color(0xFF2A3F5E)),
  );
}
