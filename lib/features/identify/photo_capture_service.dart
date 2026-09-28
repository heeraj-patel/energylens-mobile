// Adapted from kernel-app's photo capture seam for local EnergyLens onboarding.
// The image stays on the phone; only confirmed model fields are saved.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
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
      return CapturedPhoto(path: file.path, bytes: bytes);
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
