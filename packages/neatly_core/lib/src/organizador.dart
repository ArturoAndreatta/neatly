import 'dart:io';

import 'package:path/path.dart' as p;

import 'ajustes.dart';
import 'historico.dart';
import 'planejador_claude.dart';
import 'plano.dart';
import 'regras_script.dart';
import 'varredura.dart';

/// Monta o plano de [raiz] no [modo] pedido. No modo Claude, o que o Claude
/// não souber (ou se ele falhar) vai pelas regras do Script.
Future<Plano> montarPlano(
  String raiz,
  Ajustes ajustes,
  Modo modo, {
  PlanejadorClaude? claude,
}) async {
  final soltos = varrer(raiz, ajustes).soltos;
  if (soltos.isEmpty || modo == Modo.script) {
    return Plano(
      raiz: raiz,
      modo: Modo.script,
      movimentos: [for (final a in soltos) Movimento(a, destinoScript(a))],
    );
  }
  try {
    final destinos = await (claude ?? PlanejadorClaude()).planejar(
      soltos,
      pastasExistentes(raiz),
    );
    return Plano(
      raiz: raiz,
      modo: Modo.claude,
      movimentos: [
        for (final a in soltos) Movimento(a, destinos[a] ?? destinoScript(a)),
      ],
    );
  } on ErroClaude catch (e) {
    return Plano(
      raiz: raiz,
      modo: Modo.script,
      movimentos: [for (final a in soltos) Movimento(a, destinoScript(a))],
      aviso: '${e.mensagem} Usei o modo Script.',
    );
  }
}

/// "nome (2).ext" livre dentro de [pasta]. Nunca sobrescreve.
String destinoLivre(String pasta, String nome) {
  var alvo = p.join(pasta, nome);
  final base = p.basenameWithoutExtension(nome);
  final ext = p.extension(nome);
  for (
    var n = 2;
    File(alvo).existsSync() || Directory(alvo).existsSync();
    n++
  ) {
    alvo = p.join(pasta, '$base ($n)$ext');
  }
  return alvo;
}

/// Move os arquivos do plano e grava a rodada no histórico.
Rodada aplicar(Plano plano, Historico historico, {bool agendada = false}) {
  final mudancas = <Mudanca>[];
  final criadas = <String>[];
  var falhas = 0;
  for (final m in plano.movimentos) {
    final pasta = p.joinAll([plano.raiz, ...m.destino.split('/')]);
    try {
      _criarPasta(pasta, plano.raiz, criadas);
      // Sumiu ou mudou desde a prévia: fica onde está.
      final origem = File(m.arquivo.caminho);
      if (!origem.existsSync()) continue;
      final alvo = destinoLivre(pasta, m.arquivo.nome);
      origem.renameSync(alvo);
      mudancas.add(Mudanca(m.arquivo.caminho, alvo));
    } on FileSystemException {
      falhas++;
    }
  }
  final agora = DateTime.now();
  final r = Rodada(
    id: agora.microsecondsSinceEpoch.toString(),
    quando: agora,
    modo: plano.modo,
    agendada: agendada,
    raiz: plano.raiz,
    mudancas: mudancas,
    pastasCriadas: criadas,
    falhas: falhas,
    aviso: plano.aviso,
  );
  if (mudancas.isNotEmpty || falhas > 0 || plano.aviso != null) {
    historico.adicionar(r);
  }
  return r;
}

void _criarPasta(String pasta, String raiz, List<String> criadas) {
  final faltando = <String>[];
  var atual = pasta;
  while (!Directory(atual).existsSync() && p.isWithin(raiz, atual)) {
    faltando.add(atual);
    atual = p.dirname(atual);
  }
  for (final d in faltando.reversed) {
    Directory(d).createSync();
    criadas.add(d);
  }
}

/// Devolve cada arquivo da rodada ao lugar (se ainda estiver onde o Neatly
/// deixou) e apaga as pastas que ela criou e ficaram vazias.
/// Devolve quantos arquivos voltaram.
int desfazer(Rodada r, Historico historico) {
  var voltaram = 0;
  for (final m in r.mudancas.reversed) {
    final f = File(m.para);
    if (!f.existsSync()) continue;
    try {
      f.renameSync(destinoLivre(p.dirname(m.de), p.basename(m.de)));
      voltaram++;
    } on FileSystemException {
      continue;
    }
  }
  for (final d in r.pastasCriadas.reversed) {
    final dir = Directory(d);
    try {
      if (dir.existsSync() && dir.listSync().isEmpty) dir.deleteSync();
    } on FileSystemException {
      continue;
    }
  }
  r.desfeita = true;
  historico.atualizar(r);
  return voltaram;
}
