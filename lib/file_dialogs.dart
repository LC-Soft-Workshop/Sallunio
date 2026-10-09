import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

class FileRequest {
  final String title, initialPath, extension, description;
  final bool save;
  const FileRequest({
    required this.title,
    required this.initialPath,
    required this.extension,
    required this.description,
    required this.save,
  });
}

abstract class FileDialogs {
  Future<String?> choose(FileRequest request);
}

String withExtension(String path, String extension) =>
    path.toLowerCase().endsWith('.$extension') ||
        extension == 'tableo.json' && path.toLowerCase().endsWith('.json')
    ? path
    : '$path.$extension';

class WindowsFileDialogs implements FileDialogs {
  @override
  Future<String?> choose(FileRequest request) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Sélecteur natif non disponible sur cette plateforme.',
      );
    }
    final owner = _owner();
    return Isolate.run(() => _choose(request, owner));
  }
}

int _owner() {
  final user = DynamicLibrary.open('user32.dll'),
      kernel = DynamicLibrary.open('kernel32.dll');
  final handle = user.lookupFunction<IntPtr Function(), int Function()>(
    'GetForegroundWindow',
  )();
  final pid = calloc<Uint32>();
  try {
    user.lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('GetWindowThreadProcessId')(handle, pid);
    return pid.value ==
            kernel.lookupFunction<Uint32 Function(), int Function()>(
              'GetCurrentProcessId',
            )()
        ? handle
        : 0;
  } finally {
    calloc.free(pid);
  }
}

final class _OpenFileName extends Struct {
  @Uint32()
  external int size;
  @IntPtr()
  external int owner;
  @IntPtr()
  external int instance;
  external Pointer<Utf16> filter;
  external Pointer<Utf16> customFilter;
  @Uint32()
  external int maxCustom;
  @Uint32()
  external int filterIndex;
  external Pointer<Utf16> file;
  @Uint32()
  external int maxFile;
  external Pointer<Utf16> fileTitle;
  @Uint32()
  external int maxTitle;
  external Pointer<Utf16> initialDir;
  external Pointer<Utf16> title;
  @Uint32()
  external int flags;
  @Uint16()
  external int offset;
  @Uint16()
  external int extensionOffset;
  external Pointer<Utf16> defaultExtension;
  @IntPtr()
  external int data;
  external Pointer<Void> hook;
  external Pointer<Utf16> template;
  external Pointer<Void> reserved;
  @Uint32()
  external int reservedFlags;
  @Uint32()
  external int flagsEx;
}

String? _choose(FileRequest request, int owner) {
  final dll = DynamicLibrary.open('comdlg32.dll'),
      ole = DynamicLibrary.open('ole32.dll');
  final co = ole
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32),
        int Function(Pointer<Void>, int)
      >('CoInitializeEx')(nullptr, 2);
  final ofn = calloc<_OpenFileName>(), buffer = calloc<Uint16>(32768);
  final initial = File(request.initialPath.replaceAll('/', '\\')).absolute;
  final filter =
      '${request.description}\u0000${request.extension == 'image' ? '*.png;*.jpg;*.jpeg' : '*.${request.extension == 'tableo.json' ? 'json' : request.extension}'}\u0000Tous les fichiers\u0000*.*\u0000\u0000'
          .toNativeUtf16(allocator: calloc);
  final title = request.title.toNativeUtf16(allocator: calloc);
  final directory = initial.parent.path.toNativeUtf16(allocator: calloc);
  final extension =
      (request.extension == 'image'
              ? 'png'
              : request.extension == 'tableo.json'
              ? 'json'
              : request.extension)
          .toNativeUtf16(allocator: calloc);
  final filename = initial.path;
  for (var i = 0; i < filename.length && i < 32767; i++) {
    buffer[i] = filename.codeUnitAt(i);
  }
  try {
    ofn.ref
      ..size = sizeOf<_OpenFileName>()
      ..owner = owner
      ..filter = filter
      ..filterIndex = 1
      ..file = buffer.cast<Utf16>()
      ..maxFile = 32768
      ..initialDir = directory
      ..title = title
      ..defaultExtension = extension
      ..flags = 0x80000 | 0x800 | 0x8 | (request.save ? 0 : 0x1000);
    final result = dll
        .lookupFunction<
          Int32 Function(Pointer<_OpenFileName>),
          int Function(Pointer<_OpenFileName>)
        >(request.save ? 'GetSaveFileNameW' : 'GetOpenFileNameW')(ofn);
    if (result != 0) {
      final path = buffer.cast<Utf16>().toDartString();
      return request.save ? withExtension(path, request.extension) : path;
    }
    final error = dll.lookupFunction<Uint32 Function(), int Function()>(
      'CommDlgExtendedError',
    )();
    if (error != 0) {
      throw FileSystemException(
        'Dialogue Windows impossible (code ${error.toRadixString(16)}).',
      );
    }
    return null;
  } finally {
    calloc.free(ofn);
    calloc.free(buffer);
    calloc.free(filter);
    calloc.free(title);
    calloc.free(directory);
    calloc.free(extension);
    if (co >= 0) {
      ole.lookupFunction<Void Function(), void Function()>('CoUninitialize')();
    }
  }
}
