import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../../../data/services/online_gallery/quick_tag_cloud_favorites_backup_codec.dart';

Future<String?> pickQuickTagCloudBackupFile() async {
  final selected = await FilePicker.platform.pickFiles(
    type: FileType.custom, allowedExtensions: ['json', 'txt'],
    withData: false, withReadStream: true,
  );
  if (selected == null || selected.files.isEmpty) return null;
  final file = selected.files.single;
  const maximum = QuickTagCloudFavoritesBackupCodec.maximumInputBytes;
  if (file.size > maximum) {
    throw const QuickTagCloudBackupException('tooLarge');
  }
  final stream = file.readStream ??
      (file.path == null ? null : File(file.path!).openRead());
  if (stream == null) throw const QuickTagCloudBackupException('invalid');
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (bytes.length + chunk.length > maximum) {
      throw const QuickTagCloudBackupException('tooLarge');
    }
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}
