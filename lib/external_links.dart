import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

abstract class LinkOpener {
  Future<void> open(Uri uri);
}

void validateExternalLink(Uri uri) {
  if (uri.scheme != 'https' ||
      !{'github.com', 'www.legifrance.gouv.fr'}.contains(uri.host) ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort && uri.port != 443) {
    throw const FormatException('Lien HTTPS vers un site autorisé attendu.');
  }
}

class WindowsLinkOpener implements LinkOpener {
  @override
  Future<void> open(Uri uri) async {
    validateExternalLink(uri);
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
