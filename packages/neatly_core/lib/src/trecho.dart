import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'arquivo.dart';

const _texto = {
  'txt', 'md', 'csv', 'tsv', 'json', 'xml', 'yaml', 'yml', 'html', 'htm', //
  'log', 'ini', 'sql', 'py', 'js', 'ts', 'dart', 'tex', 'rtf',
};

const _office = {
  'docx': 'word/document.xml',
  'pptx': 'ppt/slides/slide1.xml',
  'xlsx': 'xl/sharedStrings.xml',
  'odt': 'content.xml',
  'ods': 'content.xml',
  'odp': 'content.xml',
};

const _limiteLeitura = 64 * 1024;
const _limiteOffice = 30 * 1024 * 1024;

/// Começo do conteúdo legível de [a], para o Claude entender o assunto.
/// Arquivo binário, grande ou ilegível devolve null.
String? trecho(ArquivoSolto a, {int caracteres = 300}) {
  try {
    String? bruto;
    if (_texto.contains(a.extensao)) {
      final raf = File(a.caminho).openSync();
      try {
        bruto = utf8.decode(raf.readSync(_limiteLeitura), allowMalformed: true);
      } finally {
        raf.closeSync();
      }
      if (a.extensao.startsWith('htm') || a.extensao == 'xml') {
        bruto = _semTags(bruto);
      }
    } else if (_office.containsKey(a.extensao) && a.tamanho < _limiteOffice) {
      final zip = ZipDecoder().decodeBytes(File(a.caminho).readAsBytesSync());
      final parte = zip.findFile(_office[a.extensao]!);
      if (parte == null) return null;
      bruto = _semTags(utf8.decode(parte.content, allowMalformed: true));
    }
    if (bruto == null) return null;
    final limpo = bruto.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (limpo.isEmpty) return null;
    return limpo.length <= caracteres ? limpo : limpo.substring(0, caracteres);
  } on Object {
    return null;
  }
}

String _semTags(String xml) => xml
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"');
