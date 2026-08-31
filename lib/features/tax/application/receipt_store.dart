import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Where a receipt photo comes from.
enum ReceiptSource { camera, gallery }

/// Keeps receipt photos on the device that took them.
///
/// The image is deliberately never uploaded. A receipt can carry a card number,
/// a signature and a home address, and storing every driver's shoebox on a
/// server is a liability with no product benefit — so the path syncs, telling a
/// second device that a record has a photo, and the photo itself stays here.
/// See [Expense.receiptPath] and the `expenses` migration, which say the same.
///
/// An interface because a widget test cannot open a camera, and because the
/// alternative is a screen that can only be exercised by hand.
abstract class ReceiptStore {
  /// Returns the stored path, or null when the driver backs out.
  Future<String?> capture(ReceiptSource source);

  /// Removes a stored photo. Safe to call for a path that is already gone.
  Future<void> discard(String? path);
}

class DeviceReceiptStore implements ReceiptStore {
  DeviceReceiptStore({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> capture(ReceiptSource source) async {
    final picked = await _picker.pickImage(
      source: source == ReceiptSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      // A receipt has to be legible, not archival. Capping the long edge keeps
      // a shoebox of them from filling the device.
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 85,
    );
    if (picked == null) return null;

    // The picker hands back a path in a cache the OS is free to reclaim, so the
    // file is copied somewhere durable before the expense records it. Without
    // this the photo would quietly disappear between sessions.
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/receipts',
    );
    if (!directory.existsSync()) await directory.create(recursive: true);

    final name =
        'receipt-${DateTime.now().microsecondsSinceEpoch}'
        '${_extension(picked.path)}';
    final saved = File('${directory.path}/$name');
    await saved.writeAsBytes(await picked.readAsBytes(), flush: true);
    return saved.path;
  }

  @override
  Future<void> discard(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // A photo that cannot be removed is not something the driver can act on,
      // and the record it belonged to is already gone.
    }
  }

  static String _extension(String path) {
    final dot = path.lastIndexOf('.');
    // Anything unrecognised is written as .jpg rather than extensionless, so
    // the platform image viewers still open it.
    if (dot == -1 || path.length - dot > 5) return '.jpg';
    return path.substring(dot);
  }
}
