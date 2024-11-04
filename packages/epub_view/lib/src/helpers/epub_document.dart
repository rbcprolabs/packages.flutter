// ignore: unnecessary_import
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'package:epubx/epubx.dart';
import 'package:flutter/services.dart';
import 'package:universal_file/universal_file.dart';

class EpubDocument {
  static Future<EpubBook> openAsset(String assetName) async {
    final byteData = await rootBundle.load(assetName);
    final bytes = byteData.buffer.asUint8List();
    return EpubReader.readBook(bytes);
  }

  static Future<EpubBook> openData(Uint8List bytes) async {
    return EpubReader.readBook(bytes);
  }

  static Future<EpubBook> openFile(File file) async {
    final bytes = await file.readAsBytes();
    return EpubReader.readBook(bytes);
  }

  static Future<EpubBook> openUrl(String url) async {
    var uri = Uri.parse(url);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      return EpubReader.readBook(response.bodyBytes);
    } else {
      throw Exception('Failed to load epub');
    }
  }


}
