import 'dart:io';

import 'package:path/path.dart' as p;

import 'ajustes.dart';
import 'arquivo.dart';
import 'regras_script.dart';

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

/// Pastas de tipo que o Neatly (1 ou 2) cria: nunca são pastas soltas.
final _deTipo = {
  for (final n in [...categorias.keys, 'Outros', 'Áudio']) n.toLowerCase(),
};

/// Pastas da raiz de [pasta] que podem sair inteiras (projetos, coisas
/// extraídas). Ficam de fora as de tipo, as que o Neatly criou
/// ([protegidas], só o nome), as ignoradas e as mexidas há pouco.
List<ArquivoSolto> pastasSoltas(
  String pasta,
  Ajustes ajustes, {
  Set<String> protegidas = const {},
  DateTime? agora,
}) {
  final dir = Directory(pasta);
  if (!dir.existsSync()) return [];
  final limite = (agora ?? DateTime.now()).subtract(
    Duration(minutes: ajustes.minutosRecentes),
  );
  final protegidasMin = {for (final n in protegidas) n.toLowerCase()};
  final saida = <ArquivoSolto>[];
  for (final e in dir.listSync(followLinks: false)) {
    if (e is! Directory) continue;
    final nome = p.basename(e.path);
    final min = nome.toLowerCase();
    if (nome.startsWith('.') || nome.startsWith(r'$')) continue;
    if (_deTipo.contains(min) || protegidasMin.contains(min)) continue;
    if (ignorado(nome, ajustes.ignorar)) continue;
    final DateTime modificado;
    try {
      modificado = e.statSync().modified;
    } on FileSystemException {
      continue;
    }
    if (modificado.isAfter(limite)) continue;
    saida.add(
      ArquivoSolto(
        caminho: e.path,
        tamanho: 0,
        modificado: modificado,
        pasta: true,
      ),
    );
  }
  saida.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
  return saida;
}

/// O que marca uma pasta como repositório ou projeto de código.
const _marcasDeProjeto = [
  '.git', 'package.json', 'pubspec.yaml', 'manifest.json', 'Cargo.toml', //
  'go.mod', 'pyproject.toml', 'requirements.txt', 'pom.xml', 'build.gradle',
  'composer.json', 'Gemfile', '.sln', '.csproj',
];

/// Repositório git ou projeto de código: o nome dela é dela (é o nome do
/// repositório, do pacote) e nunca muda.
bool ehProjeto(String pasta) {
  final List<FileSystemEntity> filhos;
  try {
    filhos = Directory(pasta).listSync(followLinks: false);
  } on FileSystemException {
    return false;
  }
  return filhos.any((f) {
    final nome = p.basename(f.path);
    return _marcasDeProjeto.any(
      (m) => m.startsWith('.') && m != '.git' ? nome.endsWith(m) : nome == m,
    );
  });
}

/// Primeiros nomes de dentro de [pasta] (subpasta com `/` no fim), para o
/// Claude entender do que ela se trata.
String espiarPasta(String pasta, {int maximo = 12}) {
  final List<FileSystemEntity> filhos;
  try {
    filhos = Directory(pasta).listSync(followLinks: false);
  } on FileSystemException {
    return '';
  }
  final nomes = [
    for (final f in filhos) '${p.basename(f.path)}${f is Directory ? '/' : ''}',
  ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  final resto = nomes.length - maximo;
  return [...nomes.take(maximo), if (resto > 0) '+$resto'].join(', ');
}

/// Subpastas que já existem (até [niveis] de profundidade), para o Claude
/// reaproveitar em vez de criar parecidas. As de [pular] (nomes da raiz)
/// ficam de fora com tudo o que têm dentro.
List<String> pastasExistentes(
  String raiz, {
  int niveis = 2,
  int maximo = 200,
  Set<String> pular = const {},
}) {
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
      if (prefixo.isEmpty && pular.contains(nome)) continue;
      final rel = prefixo.isEmpty ? nome : '$prefixo/$nome';
      saida.add(rel);
      andar(f, rel, nivel + 1);
    }
  }

  final d = Directory(raiz);
  if (d.existsSync()) andar(d, '', 1);
  return saida;
}
