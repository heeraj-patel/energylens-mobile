// Adapted from kernel-app's photo capture seam for local EnergyLens onboarding.
// The image stays on the phone; only confirmed model fields are saved.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraPermissionDeniedException implements Exception {
  const CameraPermissionDeniedException();
}

class PhotoLibraryPermissionDeniedException implements Exception {
  const PhotoLibraryPermissionDeniedException();
}

class CapturedPhoto {
  const CapturedPhoto({required this.path, required this.bytes});
  final String path;
  final Uint8List bytes;
}

/// Physically applies EXIF orientation so previews and native OCR read the
/// same upright pixels. Unreadable formats are left untouched for native OCR.
Uint8List normalizePhotoOrientation(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final upright = img.bakeOrientation(decoded);
  return Uint8List.fromList(img.encodeJpg(upright, quality: 80));
}

class PhotoCaptureService {
  const PhotoCaptureService();

  Future<CapturedPhoto?> capturePhoto() => _pick(ImageSource.camera);
  Future<CapturedPhoto?> pickFromGallery() => _pick(ImageSource.gallery);

  Future<CapturedPhoto?> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        try {
          await File(file.path).delete();
        } catch (_) {
          // The picker may remove its own temporary file.
        }
        throw const FormatException('Choose a photo smaller than 5 MB.');
      }
      final normalizedBytes = normalizePhotoOrientation(bytes);
      if (normalizedBytes.length > 5 * 1024 * 1024) {
        try {
          await File(file.path).delete();
        } catch (_) {
          // The picker may remove its own temporary file.
        }
        throw const FormatException('Choose a photo smaller than 5 MB.');
      }
      await File(file.path).writeAsBytes(normalizedBytes, flush: true);
      return CapturedPhoto(path: file.path, bytes: normalizedBytes);
    } on PlatformException catch (error) {
      if (error.code == 'camera_access_denied') {
        throw const CameraPermissionDeniedException();
      }
      if (error.code == 'photo_access_denied') {
        throw const PhotoLibraryPermissionDeniedException();
      }
      rethrow;
    }
  }

  /// Rotates into a new JPEG so native OCR reads the new pixels and a failed
  /// scan leaves the previous photo intact.
  Future<CapturedPhoto> rotateClockwise(CapturedPhoto photo) async {
    final decoded = img.decodeImage(photo.bytes);
    if (decoded == null) {
      throw StateError('Photo rotation is unavailable for this image.');
    }
    final rotated = Uint8List.fromList(
      img.encodeJpg(img.copyRotate(decoded, angle: 90), quality: 80),
    );
    if (rotated.length > 5 * 1024 * 1024) {
      throw const FormatException('Choose a photo smaller than 5 MB.');
    }
    final file = File(
      '${File(photo.path).parent.path}/energylens-rotated-${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(rotated, flush: true);
    return CapturedPhoto(path: file.path, bytes: rotated);
  }

  Future<String?> extractTextHint(String path) async {
    final recognizer = TextRecognizer();
    try {
      final text = (await recognizer.processImage(
        InputImage.fromFilePath(path),
      )).text.trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    } finally {
      try {
        await recognizer.close();
      } catch (_) {
        // Some test and desktop platforms do not install the native plugin.
      }
    }
  }

  Future<String?> detectUpc(String path) async {
    final controller = MobileScannerController();
    try {
      final capture = await controller.analyzeImage(path);
      const formats = {
        BarcodeFormat.ean8,
        BarcodeFormat.ean13,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
      };
      for (final barcode in capture?.barcodes ?? <Barcode>[]) {
        if (formats.contains(barcode.format) && barcode.rawValue != null) {
          return barcode.rawValue;
        }
      }
    } catch (_) {
      // Barcode detection is optional; OCR and manual entry remain available.
    } finally {
      try {
        await controller.dispose();
      } catch (_) {
        // Some test and desktop platforms do not install the native plugin.
      }
    }
    return null;
  }

  Future<void> discard(CapturedPhoto photo) async {
    try {
      await File(photo.path).delete();
    } catch (_) {
      /* Picker cache may have expired. */
    }
  }
}
