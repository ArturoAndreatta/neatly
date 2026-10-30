import 'dart:io';

import 'package:path/path.dart' as p;

import 'ajustes.dart';
import 'arquivo.dart';

/// Resultado de olhar a raiz da pasta.
class Varredura {
  const Varredura({required this.soltos, required this.recentes});

  /// Prontos para organizar.
  final List<ArquivoSolto> soltos;

  /// Mexidos há pouco (podem estar baixando): ficam para a próxima.
  final int recentes;
}

/// `*` e `?` como no Explorer, sem diferenciar maiúsculas.
bool casaPadrao(String nome, String padrao) {
  final re = RegExp(
    '^${RegExp.escape(padrao).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$',
    caseSensitive: false,
  );
  return re.hasMatch(nome);
}

bool ignorado(String nome, List<String> padroes) =>
    padroes.any((x) => casaPadrao(nome, x));

/// Lista os arquivos soltos na raiz de [pasta]. Nunca entra em subpastas.
Varredura varrer(String pasta, Ajustes ajustes, {DateTime? agora}) {
  final dir = Directory(pasta);
  if (!dir.existsSync()) return const Varredura(soltos: [], recentes: 0);
  final limite = (agora ?? DateTime.now()).subtract(
    Duration(minutes: ajustes.minutosRecentes),
  );
  final soltos = <ArquivoSolto>[];
  var recentes = 0;
  for (final e in dir.listSync(followLinks: false)) {
    if (e is! File) continue;
    final nome = p.basename(e.path);
    if (ignorado(nome, ajustes.ignorar)) continue;
    final ArquivoSolto a;
    try {
      a = ArquivoSolto.de(e);
    } on FileSystemException {
      continue;
    }
    if (a.modificado.isAfter(limite)) {
      recentes++;
      continue;
    }
    soltos.add(a);
  }
  soltos.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
  return Varredura(soltos: soltos, recentes: recentes);
}

/// Subpastas que já existem (até [niveis] de profundidade), para o Claude
/// reaproveitar em vez de criar parecidas.
List<String> pastasExistentes(String raiz, {int niveis = 2, int maximo = 200}) {
  final saida = <String>[];
  void andar(Directory d, String prefixo, int nivel) {
    if (nivel > niveis || saida.length >= maximo) return;
    final List<FileSystemEntity> filhos;
    try {
      filhos = d.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final f in filhos.whereType<Directory>()) {
      if (saida.length >= maximo) return;
      final nome = p.basename(f.path);
      if (nome.startsWith('.') || nome.startsWith(r'$')) continue;
      final rel = prefixo.isEmpty ? nome : '$prefixo/$nome';
      saida.add(rel);
      andar(f, rel, nivel + 1);
    }
  }

  final d = Directory(raiz);
  if (d.existsSync()) andar(d, '', 1);
  return saida;
}
