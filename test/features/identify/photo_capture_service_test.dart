import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:energylens_mobile/features/identify/photo_capture_service.dart';

void main() {
  test('EXIF upside-down orientation is baked into the preview pixels', () {
    final source = img.Image(width: 32, height: 16);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, x < source.width ~/ 2 ? 255 : 0, 0, 0);
      }
    }
    source.exif.imageIfd.orientation = 3;
    final encoded = Uint8List.fromList(img.encodeJpg(source, quality: 100));

    final normalized = normalizePhotoOrientation(encoded);
    final result = img.decodeImage(normalized)!;

    expect(result.exif.imageIfd.hasOrientation, isFalse);
    expect(result.getPixel(27, 8).r, greaterThan(result.getPixel(4, 8).r));
  });

  test('clockwise rotation updates the OCR file and pixel dimensions', () async {
    final directory = await Directory.systemTemp.createTemp('energylens-photo-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/label.jpg');
    final source = img.Image(width: 32, height: 16);
    source.setPixelRgb(4, 8, 255, 0, 0);
    final bytes = Uint8List.fromList(img.encodeJpg(source, quality: 100));
    await file.writeAsBytes(bytes);

    final rotated = await const PhotoCaptureService().rotateClockwise(
      CapturedPhoto(path: file.path, bytes: bytes),
    );
    final result = img.decodeImage(await file.readAsBytes())!;

    expect(rotated.path, file.path);
    expect(rotated.bytes, await file.readAsBytes());
    expect(result.width, 16);
    expect(result.height, 32);
    expect(result.exif.imageIfd.hasOrientation, isFalse);
  });
}
