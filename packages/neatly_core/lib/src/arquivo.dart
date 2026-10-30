import 'dart:io';

import 'package:path/path.dart' as p;

/// Arquivo solto na raiz da pasta organizada.
class ArquivoSolto {
  ArquivoSolto({
    required this.caminho,
    required this.tamanho,
    required this.modificado,
  });

  factory ArquivoSolto.de(File f) {
    final s = f.statSync();
    return ArquivoSolto(
      caminho: f.path,
      tamanho: s.size,
      modificado: s.modified,
    );
  }

  final String caminho;
  final int tamanho;
  final DateTime modificado;

  String get nome => p.basename(caminho);

  /// Extensão em minúsculas, sem o ponto ('' quando não tem).
  String get extensao {
    final e = p.extension(caminho);
    return e.isEmpty ? '' : e.substring(1).toLowerCase();
  }
}
