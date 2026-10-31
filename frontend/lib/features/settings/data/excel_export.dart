import 'dart:io';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:finance_app/data/finance_provider.dart';

/// Tạo tệp Excel (.xlsx – Office Open XML) gồm các trang Giao dịch, Ví, Ngân sách.
class ExcelExport {
  static String _esc(Object? v) => '${v ?? ''}'
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

  static String _col(int i) {
    var n = i + 1, s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static String _sheet(List<List<Object?>> rows) {
    final b = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetData>');
    for (var r = 0; r < rows.length; r++) {
      b.write('<row r="${r + 1}">');
      for (var c = 0; c < rows[r].length; c++) {
        final ref = '${_col(c)}${r + 1}';
        final v = rows[r][c];
        final style = r == 0 ? ' s="1"' : '';
        if (v is num && r > 0) {
          b.write('<c r="$ref"$style><v>$v</v></c>');
        } else {
          b.write(
              '<c r="$ref" t="inlineStr"$style><is><t xml:space="preserve">${_esc(v)}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }

  /// Các trang tính (tên, dữ liệu) từ sổ cái.
  static List<(String, List<List<Object?>>)> sheets(FinanceProvider p) {
    final f = DateFormat('dd/MM/yyyy HH:mm');
    final d = DateFormat('dd/MM/yyyy');
    return [
      (
        'Giao dịch',
        [
          ['Ngày', 'Loại', 'Số tiền', 'Tiền tệ', 'Ví', 'Ví nhận', 'Danh mục', 'Đối tượng', 'Ghi chú', 'Hạn trả', 'Không tính báo cáo'],
          for (final e in [...p.entries]..sort((a, b) => b.date.compareTo(a.date)))
            [
              f.format(e.date),
              e.kind.label,
              e.amount,
              p.findWallet(e.walletId)?.currency ?? '',
              p.findWallet(e.walletId)?.name ?? '',
              p.findWallet(e.destinationId)?.name ?? '',
              p.category(e.categoryId)?.name ?? '',
              p.personName(e.personId),
              e.note,
              e.dueDate == null ? '' : d.format(e.dueDate!),
              e.excluded ? 'Có' : '',
            ]
        ]
      ),
      (
        'Ví',
        [
          ['Tên ví', 'Loại', 'Tiền tệ', 'Số dư ban đầu', 'Số dư hiện tại', 'Mục tiêu', 'Ngày bắt đầu', 'Ngày kết thúc'],
          for (final w in p.wallets)
            [
              w.name,
              w.savings ? 'Tiết kiệm' : 'Cơ bản',
              w.currency,
              w.opening,
              p.balance(w.id),
              w.savings ? w.target : '',
              w.startDate == null ? '' : d.format(w.startDate!),
              w.deadline == null ? '' : d.format(w.deadline!),
            ]
        ]
      ),
      (
        'Ngân sách',
        [
          ['Tháng', 'Danh mục', 'Loại', 'Ví', 'Tiền tệ', 'Mục tiêu', 'Đã dùng', 'Còn lại'],
          for (final b in p.budgets)
            [
              DateFormat('MM/yyyy').format(b.month),
              b.categoryId == null ? 'Tổng cả tháng' : p.category(b.categoryId)?.name ?? '',
              p.budgetIncome(b) ? 'Thu nhập' : 'Chi tiêu',
              b.walletId == null ? 'Tất cả ví' : p.findWallet(b.walletId)?.name ?? '',
              b.currency,
              b.amount,
              p.used(b),
              b.amount - p.used(b),
            ]
        ]
      ),
    ];
  }

  static List<int> build(FinanceProvider p) {
    final list = sheets(p);
    final archive = Archive();
    void add(String name, String content) =>
        archive.addFile(ArchiveFile.string(name, content));
    add('[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var i = 1; i <= list.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>');
    add('_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>');
    add('xl/workbook.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        '${[for (var i = 1; i <= list.length; i++) '<sheet name="${_esc(list[i - 1].$1)}" sheetId="$i" r:id="rId$i"/>'].join()}'
        '</sheets></workbook>');
    add('xl/_rels/workbook.xml.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 1; i <= list.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
        '<Relationship Id="rId${list.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>');
    add('xl/styles.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
        '</styleSheet>');
    for (var i = 0; i < list.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheet(list[i].$2));
    }
    return ZipEncoder().encode(archive);
  }

  /// Ghi tệp vào thư mục tạm rồi mở bảng chia sẻ của hệ điều hành.
  static Future<void> share(FinanceProvider p, {bool csv = false}) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final file = File('${dir.path}/chi_tieu_$stamp.${csv ? 'csv' : 'xlsx'}');
    if (csv) {
      await file.writeAsString(p.exportCsv());
    } else {
      await file.writeAsBytes(build(p));
    }
    await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: 'Dữ liệu chi tiêu',
        text: 'Dữ liệu quản lý chi tiêu xuất ngày ${DateFormat('dd/MM/yyyy').format(DateTime.now())}'));
  }
}
