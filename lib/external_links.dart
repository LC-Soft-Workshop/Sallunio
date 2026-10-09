import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

abstract class LinkOpener {
  Future<void> open(Uri uri);
}

class WindowsLinkOpener implements LinkOpener {
  @override
  Future<void> open(Uri uri) async {
    if (uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Lien GitHub sécurisé attendu.');
    }
    if (!Platform.isWindows) {
      throw const FileSystemException(
        'Ouverture de lien Windows indisponible.',
      );
    }
    final shell = DynamicLibrary.open('shell32.dll');
    final execute = shell
        .lookupFunction<
          IntPtr Function(
            Pointer<Void>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Int32,
          ),
          int Function(
            Pointer<Void>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            int,
          )
        >('ShellExecuteW');
    final operation = 'open'.toNativeUtf16();
    final address = uri.toString().toNativeUtf16();
    try {
      if (execute(nullptr, operation, address, nullptr, nullptr, 1) <= 32) {
        throw const FileSystemException(
          'Le navigateur n’a pas pu être ouvert.',
        );
      }
    } finally {
      calloc.free(operation);
      calloc.free(address);
    }
  }
}
