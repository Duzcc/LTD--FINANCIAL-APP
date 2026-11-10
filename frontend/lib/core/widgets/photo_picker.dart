import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:finance_app/core/widgets/finance_ui.dart';

// Ảnh vừa chụp nằm trong thư mục tạm, hệ điều hành có thể xóa bất cứ lúc nào,
// nên chép sang thư mục riêng của ứng dụng để ảnh còn mãi cùng giao dịch.
Future<String> _keep(String source) async {
  final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/receipts');
  await dir.create(recursive: true);
  return (await File(source).copy('${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg')).path;
}

Future<String?> choosePhoto(BuildContext context, ImageSource source,
    {double maxWidth = 2200, int quality = 90}) async {
  String? path;
  final failure = await failureOf(() async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: maxWidth, imageQuality: quality);
    if (file != null) path = await _keep(file.path);
  });
  if (failure != null && context.mounted) {
    message(context, 'Không lấy được ảnh. Hãy cho phép ứng dụng dùng camera và thư viện ảnh.');
  }
  return path;
}
