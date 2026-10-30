import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Dart port of `atlas-dev/backend/apps/grading/services/bubble_sheet_generator.py`
/// so quick-exam sheets look and scan exactly like web sheets. Up to 72 items
/// use the web's two answer columns; 73–100 items switch to three columns at the
/// same row pitch so every bubble stays inside the ArUco frame.
class QuickSheet {
  /// Quick exams are 50–100 items; smaller quizzes aren't offered.
  static const int minItems = 50;
  static const int maxItems = 100;
  static const int twoColumnMaxItems = 72;

  static const double _pageW = 215.9;
  static const double _pageH = 330.2;
  static const double _headerMm = 50.8;
  static const double _fidSpan = 254.0;
  static const double _mm2pt = 72.0 / 25.4;

  static const double _fidInset = 5.0;
  static const double _fidW = 15.0;
  static const double _fidQuiet = 2.0;
  static const double _contentTop = _headerMm;
  static const double _contentBot = _contentTop + _fidSpan - _fidW;

  static const double _xShift = 3.0;
  static const double _leftX0 = 20.0 + _xShift;
  static const double _leftX1 = 78.0 + _xShift;
  static const double _leftW = _leftX1 - _leftX0;

  static const double _qrSize = 52.0;
  static const double _qrX0 = _leftX0 + (_leftW - _qrSize) / 2;
  static const double _qrQuietMm = 3.0;

  static const int _combN = 8;
  static const double _combW = 5.5;
  static const double _combH = 6.5;
  static const double _combGap = 1.0;
  static const double _combTotal = _combN * _combW + (_combN - 1) * _combGap;
  static const double _combX0 = _leftX0 + (_leftW - _combTotal) / 2;

  static const double _idBubbleR = 1.75;
  static const double _idRowPitch = 5.0;
  static const double _idLabelX = _combX0 - 3.0;
  static const List<String> _idLabels = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '-',
  ];

  static const double _rightX0 = 80.0 + _xShift;
  static const double _rightX1 = 190.0 + _xShift;
  static const double _rightW = _rightX1 - _rightX0;
  static const double _colGap = 1.5;
  static const double _headerBarH = 8.0;
  static const double _rowPitch = 6.0;
  static const double _bubbleR = 2.0;
  static const int _capacity = 100;

  static const List<List<List<int>>> _aruco = [
    [[1, 0, 1, 1], [0, 1, 0, 1], [0, 0, 1, 1], [0, 0, 1, 0]],
    [[0, 0, 0, 0], [1, 1, 1, 1], [1, 0, 0, 1], [1, 0, 1, 0]],
    [[0, 0, 1, 1], [0, 0, 1, 1], [0, 0, 1, 0], [1, 1, 0, 1]],
    [[1, 0, 0, 1], [1, 0, 0, 1], [0, 1, 0, 0], [0, 1, 1, 0]],
  ];
  static const List<(double, double, int, String)> _fidSpec = [
    (_fidInset, _contentTop, 0, 'TL'),
    (_pageW - _fidInset - _fidW, _contentTop, 1, 'TR'),
    (_pageW - _fidInset - _fidW, _contentBot, 2, 'BR'),
    (_fidInset, _contentBot, 3, 'BL'),
  ];

  static double _pt(double mm) => mm * _mm2pt;
  static double _r2(double v) => (v * 100).roundToDouble() / 100;

  /// Half-page sheets: two copies per long-bond page, cut apart. The ID grid
  /// sets the height, so the answer grid fits 20 rows (two columns).
  static const int compactMaxItems = 40;
  static const double _halfH = _pageH / 2;
  static const double _compactFidTop = 15.0;
  static const double _compactY0 = 21.0;
  // QR + gap + comb + gap + 11 ID rows down to the last bubble's edge.
  static const double _leftZoneH =
      _qrSize + 10 + _combH + 6 + 2.5 + 10 * _idRowPitch + _idBubbleR;

  /// Number of answer columns the sheet uses for [totalItems].
  static int columnsFor(int totalItems) =>
      totalItems <= twoColumnMaxItems ? 2 : 3;

  /// True when a half-page layout can hold [totalItems].
  static bool fitsCompact(int totalItems) => totalItems <= compactMaxItems;

  /// Whether stored `layout_metadata` describes a half-page sheet.
  static bool isCompactLayout(Map<String, dynamic>? layout) =>
      layout?['sheet_style'] == 'compact';

  static _Geometry _geometry(int total, int idCols, {bool compact = false}) {
    final cols = columnsFor(total);
    final colW = (_rightW - (cols - 1) * _colGap) / cols;
    final itemW = cols == 2 ? 8.0 : 7.5;
    final step = cols == 2 ? 10.0 : 7.5;
    final ipc = cols == 2 ? (total + 1) ~/ 2 : (total / 3).ceil();
    final avlTop = _contentTop + _fidW;
    final avlH = _contentBot - avlTop;
    final gridH = _headerBarH + ipc * _rowPitch;
    final y0 = compact ? _compactY0 : avlTop + (avlH - gridH) / 2.0;
    final compactFidBot = _compactY0 + _leftZoneH + 2 - _fidW;
    final fids = compact
        ? <(double, double, int, String)>[
            (_fidInset, _compactFidTop, 0, 'TL'),
            (_pageW - _fidInset - _fidW, _compactFidTop, 1, 'TR'),
            (_pageW - _fidInset - _fidW, compactFidBot, 2, 'BR'),
            (_fidInset, compactFidBot, 3, 'BL'),
          ]
        : _fidSpec;
    final x0s = [for (var i = 0; i < cols; i++) _rightX0 + i * (colW + _colGap)];
    final idCentres = [
      for (var i = 0; i < _combN; i++)
        _combX0 + _combW / 2 + i * (_combW + _combGap),
    ];
    return _Geometry(
      total: total,
      cols: cols,
      colW: colW,
      itemW: itemW,
      step: step,
      ipc: ipc,
      y0: y0,
      x0s: x0s,
      idCols: math.min(math.max(idCols, 1), _combN),
      idCentres: idCentres,
      fids: fids,
      compact: compact,
    );
  }

  static Map<String, double> _bubbleXs(_Geometry g, double x0) {
    final leftover = g.colW - g.itemW - 3 * g.step;
    final offset = g.itemW + leftover / 2;
    return {
      for (var j = 0; j < 4; j++) 'ABCD'[j]: x0 + offset + j * g.step,
    };
  }

  /// Bubble positions in the same shape the web generator stores, so the
  /// on-device OMR engine can read quick-exam sheets unchanged.
  static Map<String, dynamic> layout({
    required int totalItems,
    required int numChoices,
    int idColumns = 8,
    bool compact = false,
  }) {
    final g = _geometry(totalItems, idColumns, compact: compact && fitsCompact(totalItems));
    final labels = 'ABCD'.substring(0, numChoices).split('');

    final fids = <Map<String, dynamic>>[
      for (final (x, y, id, corner) in g.fids)
        {
          'x_mm': _r2(x),
          'y_spec_mm': _r2(y),
          'w_mm': _fidW,
          'h_mm': _fidW,
          'size_mm': _fidW,
          'id': id,
          'corner': corner,
        },
    ];
    final bl = g.fids[3], br = g.fids[2];

    final combY = g.y0 + _qrSize + 10;
    final idGridTop = combY + _combH + 6;

    final items = <String, dynamic>{};
    final grid = <String, dynamic>{
      'y_start_spec_mm': g.y0,
      'header_h_mm': _headerBarH,
      'row_pitch_mm': _rowPitch,
      'bubble_r_mm': _bubbleR,
      'answer_zone_x0_mm': _rightX0,
      'answer_zone_x1_mm': _rightX1,
      'col_width_mm': g.colW,
      'col_gap_mm': _colGap,
      'num_choices': numChoices,
      'num_columns': g.cols,
    };
    const colKeys = ['col_a', 'col_b', 'col_c'];
    for (var ci = 0; ci < g.cols; ci++) {
      final x0 = g.x0s[ci];
      final start = ci * g.ipc + 1;
      final bx = _bubbleXs(g, x0);
      grid[colKeys[ci]] = {
        'x0_mm': x0,
        'y_start_spec_mm': g.y0,
        'y_bottom_spec_mm': g.y0 + _headerBarH + g.ipc * _rowPitch,
        'start_item': start,
      };
      for (var ri = 0; ri < g.ipc; ri++) {
        final ino = start + ri;
        if (ino > totalItems) break;
        final rc = g.y0 + _headerBarH + ri * _rowPitch + _rowPitch / 2;
        items['$ino'] = {
          for (final l in labels)
            l: {'cx_mm': _r2(bx[l]!), 'cy_spec_mm': _r2(rc)},
        };
      }
    }

    return {
      'page_width_pt': _r2(_pt(_pageW)),
      'page_height_pt': _r2(_pt(_pageH)),
      'page': g.compact ? 'Half Long Bond (2 per 8.5"x13")' : 'Long Bond (8.5"x13")',
      'sheet_style': g.compact ? 'compact' : 'full',
      'capacity': _capacity,
      'total_items': totalItems,
      'rows_per_column': g.cols == 2 ? _capacity ~/ 2 : g.ipc,
      'num_answer_columns': g.cols,
      'num_id_columns': g.idCols,
      'row_height_pt': _r2(_pt(_rowPitch)),
      'bubble_radius_pt': _r2(_pt(_bubbleR)),
      'dpi': 300,
      'items': items,
      'id_columns': {
        'x0_mm': g.idCentres.first,
        'y_top_spec_mm': idGridTop,
        'num_cols': g.idCols,
        'bubble_r_mm': _idBubbleR,
        'col_pitch_mm': _combW + _combGap,
        'row_pitch_mm': _idRowPitch,
      },
      'left_zone': {
        'x0_mm': _leftX0,
        'x1_mm': _leftX1,
        'qr_x0_mm': _qrX0,
        'qr_size_mm': _qrSize,
        'y_start_spec_mm': g.y0,
      },
      'fiducial_type': 'aruco_4x4_50',
      'aruco_dict': 'DICT_4X4_50',
      'fiducials': fids,
      'fiducial_baseline_ref': _r2(
        math.sqrt(math.pow(br.$1 - bl.$1, 2) + math.pow(br.$2 - bl.$2, 2)),
      ),
      'answer_grid': grid,
      'parts': [
        for (var i = 0; i < g.cols; i++)
          if (i * g.ipc + 1 <= totalItems)
            {
              'label': 'Col ${String.fromCharCode(65 + i)}',
              'start_item': i * g.ipc + 1,
              'end_item': math.min((i + 1) * g.ipc, totalItems),
            },
      ],
    };
  }

  /// One long-bond PDF page for the exam, encoding [qrPayload] in the QR.
  /// [compact] prints two identical half-page copies with a cut line.
  static Future<Uint8List> buildPdf({
    required int totalItems,
    required int numChoices,
    required String qrPayload,
    int idColumns = 8,
    bool compact = false,
    String title = '',
  }) async {
    final g = _geometry(totalItems, idColumns, compact: compact && fitsCompact(totalItems));
    final doc = pw.Document();
    final regular = PdfFont.helvetica(doc.document);
    final bold = PdfFont.helveticaBold(doc.document);
    final pageFormat = PdfPageFormat(_pt(_pageW), _pt(_pageH));
    final offsets = g.compact ? const [0.0, _halfH] : const [0.0];

    pw.Widget qr(double dy) => pw.Positioned(
          left: _pt(_qrX0),
          top: _pt(g.y0 + dy),
          child: pw.Container(
            width: _pt(_qrSize),
            height: _pt(_qrSize),
            color: PdfColors.white,
            padding: pw.EdgeInsets.all(_pt(_qrQuietMm)),
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(
                errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium,
              ),
              data: qrPayload,
              drawText: false,
            ),
          ),
        );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            pw.CustomPaint(
              size: PdfPoint(pageFormat.width, pageFormat.height),
              painter: (canvas, _) {
                for (final dy in offsets) {
                  _paint(canvas, g, numChoices, regular, bold, dy: dy, title: title);
                }
                if (g.compact) _paintCutLine(canvas, regular);
              },
            ),
            for (final dy in offsets) qr(dy),
          ],
        ),
      ),
    );
    return doc.save();
  }

  // ── Drawing (PDF origin bottom-left; spec y is top-origin mm) ──────────

  static double _sy(double specY) => _pt(_pageH - specY);

  /// Name line above a half-page copy (inside its own half, above the markers).
  static void _paintNameStrip(PdfGraphics c, PdfFont regular, PdfFont bold,
      double dy, String title) {
    final y = _sy(dy + 10);
    var safe = title
        .replaceAll(RegExp('[\u2012-\u2015]'), '-')
        .replaceAll(RegExp('[\u2018\u2019]'), "'")
        .replaceAll(RegExp('[\u201C\u201D]'), '"')
        .replaceAll(RegExp(r'[^\x20-\xFF]'), '')
        .trim();
    if (safe.length > 48) safe = '${safe.substring(0, 47)}...';
    _text(c, bold, 8, safe.isEmpty ? 'QUIZ' : safe, _pt(_leftX0), y);
    _text(c, regular, 8, 'Name: ______________________________', _pt(110 + _xShift), y);
  }

  static void _paintCutLine(PdfGraphics c, PdfFont regular) {
    final y = _sy(_halfH);
    c
      ..saveContext()
      ..setLineDashPattern([4, 3])
      ..setStrokeColor(const PdfColor(0.55, 0.55, 0.55))
      ..setLineWidth(0.6)
      ..moveTo(_pt(4), y)
      ..lineTo(_pt(_pageW - 4), y)
      ..strokePath()
      ..restoreContext();
    _text(c, regular, 6, 'cut here', _pt(_pageW / 2), y + 2,
        align: 'center', color: const PdfColor(0.55, 0.55, 0.55));
  }

  static const PdfColor _brandGreen = PdfColor(0.082, 0.502, 0.239); // #8E1C1B
  static const PdfColor _darkHdr = PdfColor(0.133, 0.133, 0.133);
  static const PdfColor _border = PdfColor(0.35, 0.35, 0.35);
  static const PdfColor _shade = PdfColor(0.933, 0.933, 0.933);
  static const PdfColor _ring = PdfColor(0.12, 0.12, 0.12);

  static void _text(
    PdfGraphics c,
    PdfFont font,
    double size,
    String s,
    double x,
    double y, {
    String align = 'left',
    PdfColor color = PdfColors.black,
  }) {
    final w = font.stringMetrics(s).width * size;
    final dx = align == 'center' ? w / 2 : (align == 'right' ? w : 0.0);
    c
      ..setFillColor(color)
      ..drawString(font, size, s, x - dx, y);
  }

  static void _rect(PdfGraphics c, double x, double y, double w, double h,
      {PdfColor? fill, PdfColor? stroke, double lineWidth = 0.5}) {
    c.drawRect(x, y, w, h);
    if (fill != null) {
      c
        ..setFillColor(fill)
        ..fillPath();
    } else if (stroke != null) {
      c
        ..setStrokeColor(stroke)
        ..setLineWidth(lineWidth)
        ..strokePath();
    }
  }

  static void _circle(PdfGraphics c, double cx, double cy, double r) {
    c
      ..drawEllipse(cx, cy, r, r)
      ..setStrokeColor(_ring)
      ..setLineWidth(0.4)
      ..strokePath();
  }

  static void _paint(
    PdfGraphics c,
    _Geometry g,
    int numChoices,
    PdfFont regular,
    PdfFont bold, {
    double dy = 0,
    String title = '',
  }) {
    double sy(double v) => _sy(v + dy);
    for (final (x, y, id, _) in g.fids) {
      _drawAruco(c, x, y, id, dy: dy);
    }
    if (g.compact) _paintNameStrip(c, regular, bold, dy, title);

    // Left zone: QR label, student ID comb + bubble grid.
    _text(c, bold, 6, 'ASSESSMENT QR', _pt(_qrX0 + _qrSize / 2),
        sy(g.y0 - 4),
        align: 'center', color: const PdfColor(0.4, 0.4, 0.4));
    final combY = g.y0 + _qrSize + 10;
    final combWidth = g.idCols * _combW + (g.idCols - 1) * _combGap;
    _text(c, bold, 8, 'STUDENT ID', _pt(_combX0 + combWidth / 2),
        sy(combY - 4),
        align: 'center', color: _brandGreen);
    for (var i = 0; i < g.idCols; i++) {
      final bx = _combX0 + i * (_combW + _combGap);
      _rect(c, _pt(bx), sy(combY + _combH), _pt(_combW), _pt(_combH),
          stroke: _border);
    }
    final idGridTop = combY + _combH + 6;
    for (var r = 0; r < _idLabels.length; r++) {
      final ry = sy(idGridTop + 2.5 + r * _idRowPitch);
      _text(c, bold, 6.5, _idLabels[r], _pt(_idLabelX), ry - 2,
          align: 'right');
      for (var col = 0; col < g.idCols; col++) {
        _circle(c, _pt(g.idCentres[col]), ry, _pt(_idBubbleR));
      }
    }

    // Answer columns.
    final labels = 'ABCD'.substring(0, numChoices).split('');
    for (var ci = 0; ci < g.cols; ci++) {
      final x0 = g.x0s[ci];
      final start = ci * g.ipc + 1;
      final bx = _bubbleXs(g, x0);
      final ix = x0 + g.itemW - 1.0;

      _rect(c, _pt(x0), sy(g.y0 + _headerBarH), _pt(g.colW), _pt(_headerBarH),
          fill: _darkHdr);
      final hy = sy(g.y0 + _headerBarH / 2);
      _text(c, bold, 9, '#', _pt(x0 + g.itemW / 2), hy,
          align: 'center', color: PdfColors.white);
      for (final l in labels) {
        _text(c, bold, 9, l, _pt(bx[l]!), hy,
            align: 'center', color: PdfColors.white);
      }

      for (var ri = 0; ri < g.ipc; ri++) {
        final ino = start + ri;
        if (ino > g.total) break;
        final rt = g.y0 + _headerBarH + ri * _rowPitch;
        final cy = sy(rt + _rowPitch / 2);
        if ((ri ~/ 5) % 2 == 1) {
          _rect(c, _pt(x0), sy(rt + _rowPitch), _pt(g.colW), _pt(_rowPitch),
              fill: _shade);
        }
        _text(c, ino % 5 == 0 ? bold : regular, 7, '$ino.', _pt(ix), cy - 2.5,
            align: 'right');
        for (final l in labels) {
          _circle(c, _pt(bx[l]!), cy, _pt(_bubbleR));
        }
      }

      final gh = _headerBarH + g.ipc * _rowPitch;
      _rect(c, _pt(x0), sy(g.y0 + gh), _pt(g.colW), _pt(gh), stroke: _border);
    }
  }

  static void _drawAruco(PdfGraphics c, double x, double y, int id, {double dy = 0}) {
    double sy(double v) => _sy(v + dy);
    const modules = 6;
    const cell = _fidW / modules;
    const overlap = 0.04;
    _rect(c, _pt(x - _fidQuiet), sy(y + _fidW + _fidQuiet),
        _pt(_fidW + 2 * _fidQuiet), _pt(_fidW + 2 * _fidQuiet),
        fill: PdfColors.white);
    final bits = _aruco[id];
    for (var row = 0; row < modules; row++) {
      for (var col = 0; col < modules; col++) {
        final edge = row == 0 || row == modules - 1 || col == 0 || col == modules - 1;
        final black = edge || bits[row - 1][col - 1] == 0;
        if (!black) continue;
        _rect(c, _pt(x + col * cell), sy(y + row * cell + cell + overlap),
            _pt(cell + overlap), _pt(cell + overlap),
            fill: PdfColors.black);
      }
    }
  }
}

class _Geometry {
  final int total;
  final int cols;
  final double colW;
  final double itemW;
  final double step;
  final int ipc;
  final double y0;
  final List<double> x0s;
  final int idCols;
  final List<double> idCentres;
  final List<(double, double, int, String)> fids;
  final bool compact;

  const _Geometry({
    required this.total,
    required this.cols,
    required this.colW,
    required this.itemW,
    required this.step,
    required this.ipc,
    required this.y0,
    required this.x0s,
    required this.idCols,
    required this.idCentres,
    required this.fids,
    required this.compact,
  });
}
