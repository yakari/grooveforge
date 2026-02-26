import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class Sf2Parser {
  /// Parses an SF2 file and returns a map of Bank -> Program -> Preset Name
  static Future<Map<int, Map<int, String>>> parsePresets(String path) async {
    final Map<int, Map<int, String>> presets = {};
    
    try {
      final file = File(path);
      if (!file.existsSync()) return presets;

      final bytes = await file.readAsBytes();
      final data = ByteData.view(bytes.buffer);
      
      int offset = 0;
      
      String readString(int start, int length) {
        return ascii.decode(bytes.sublist(start, start + length), allowInvalid: true);
      }

      if (bytes.length < 12) return presets;
      
      String header = readString(offset, 4);
      if (header != 'RIFF') return presets;
      offset += 8;
      
      String format = readString(offset, 4);
      if (format != 'sfbk') return presets;
      offset += 4;
      
      while (offset < bytes.length) {
        if (offset + 8 > bytes.length) break;
        
        String chunkId = readString(offset, 4);
        int chunkSize = data.getUint32(offset + 4, Endian.little);
        
        if (chunkId == 'LIST') {
          String listType = readString(offset + 8, 4);
          if (listType == 'pdta') {
            int pdtaOffset = offset + 12;
            int pdtaEnd = offset + 8 + chunkSize;
            
            while (pdtaOffset < pdtaEnd) {
               if (pdtaOffset + 8 > bytes.length) break;
               String subChunkId = readString(pdtaOffset, 4);
               int subChunkSize = data.getUint32(pdtaOffset + 4, Endian.little);
               
               if (subChunkId == 'phdr') {
                  int presetCount = subChunkSize ~/ 38; 
                  for (int i=0; i < presetCount - 1; i++) { 
                     int pOffset = pdtaOffset + 8 + (i * 38);
                     if (pOffset + 38 > bytes.length) break;
                     
                     String pName = readString(pOffset, 20).replaceAll(RegExp(r'\x00.*'), '');
                     int pId = data.getUint16(pOffset + 20, Endian.little);
                     int pBank = data.getUint16(pOffset + 22, Endian.little);
                     
                     presets.putIfAbsent(pBank, () => {});
                     presets[pBank]![pId] = pName;
                  }
                  return presets; // Found what we need, can stop parsing
               }
               pdtaOffset += 8 + subChunkSize;
               if (subChunkSize % 2 != 0) pdtaOffset++; 
            }
          }
        }
        
        offset += 8 + chunkSize;
        if (chunkSize % 2 != 0) offset++;
      }
    } catch (e) {
      debugPrint('Error parsing SF2 presets: $e');
    }
    
    return presets;
  }
}
