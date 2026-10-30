import 'arquivo.dart';

/// Pasta genérica de cada extensão.
const categorias = <String, List<String>>{
  'Imagens': [
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'heic', 'heif', 'bmp', //
    'tif', 'tiff', 'ico', 'avif', 'raw', 'cr2', 'nef', 'psd', 'ai',
  ],
  'Vídeos': ['mp4', 'mkv', 'mov', 'avi', 'webm', 'wmv', 'flv', 'm4v', '3gp'],
  'Áudios': ['mp3', 'wav', 'flac', 'ogg', 'opus', 'm4a', 'aac', 'wma', 'mid'],
  'Documentos': [
    'pdf', 'doc', 'docx', 'odt', 'rtf', 'txt', 'md', 'epub', 'mobi', //
    'pages', 'tex',
  ],
  'Planilhas': ['xls', 'xlsx', 'xlsm', 'ods', 'csv', 'tsv', 'numbers'],
  'Apresentações': ['ppt', 'pptx', 'odp', 'key'],
  'Instaladores': ['exe', 'msi', 'msix', 'msixbundle', 'appx', 'apk', 'dmg'],
  'Compactados': ['zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz', 'iso'],
  'Código': [
    'json', 'xml', 'yaml', 'yml', 'html', 'htm', 'css', 'js', 'ts', //
    'py', 'dart', 'java', 'c', 'cpp', 'cs', 'go', 'rs', 'sql', 'sh', //
    'ps1', 'bat', 'cmd', 'ipynb',
  ],
  'Fontes': ['ttf', 'otf', 'woff', 'woff2'],
  'Torrents': ['torrent'],
  '3D': ['stl', 'obj', 'fbx', 'blend', '3mf', 'gcode'],
};

const _outros = 'Outros';

final _extensaoParaPasta = {
  for (final e in categorias.entries)
    for (final ext in e.value) ext: e.key,
};

/// Subpasta por padrão de nome, dentro da pasta do tipo.
final _padroesNome = <(RegExp, String, Set<String>?)>[
  (
    RegExp(
      r'^(screenshot|captura de tela|print|snip|recorte)',
      caseSensitive: false,
    ),
    'Capturas',
    {'Imagens', 'Vídeos'},
  ),
  (RegExp('whatsapp', caseSensitive: false), 'WhatsApp', null),
  (
    RegExp(
      r'(boleto|fatura|nota[ _-]?fiscal|\bnfs?-?e?\b|danfe|comprovante|extrato|recibo|invoice|receipt)',
      caseSensitive: false,
    ),
    'Finanças',
    {'Documentos', 'Imagens', 'Planilhas'},
  ),
  (
    RegExp(r'(curr[ií]culo|resume|\bcv\b)', caseSensitive: false),
    'Currículos',
    {'Documentos'},
  ),
];

/// Pasta (relativa, com `/`) do modo Script para [a].
String destinoScript(ArquivoSolto a) {
  final tipo = _extensaoParaPasta[a.extensao] ?? _outros;
  for (final (re, sub, so) in _padroesNome) {
    if ((so == null || so.contains(tipo)) && re.hasMatch(a.nome)) {
      return '$tipo/$sub';
    }
  }
  return tipo;
}
