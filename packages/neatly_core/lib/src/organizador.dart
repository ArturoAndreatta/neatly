import 'dart:io';

import 'package:path/path.dart' as p;

import 'ajustes.dart';
import 'arquivo.dart';
import 'historico.dart';
import 'nomes.dart';
import 'planejador_claude.dart';
import 'plano.dart';
import 'regras_script.dart';
import 'varredura.dart';

/// Nomes das pastas da raiz que o Neatly criou (rodadas não desfeitas):
/// são dele, nunca pastas soltas.
Set<String> pastasDoNeatly(String raiz, List<Rodada> rodadas) => {
  for (final r in rodadas)
    if (!r.desfeita && p.equals(r.raiz, raiz))
      for (final d in r.pastasCriadas)
        if (p.equals(p.dirname(d), raiz)) p.basename(d),
};

/// Monta o plano de [raiz] no [modo] pedido. No modo Claude, o que o Claude
/// não souber (ou se ele falhar) vai pelas regras do Script, e as pastas
/// soltas (fora as de [rodadas]) também podem ir inteiras para um tema.
Future<Plano> montarPlano(
  String raiz,
  Ajustes ajustes,
  Modo modo, {
  PlanejadorClaude? claude,
  List<Rodada> rodadas = const [],
}) async {
  final soltos = varrer(raiz, ajustes).soltos;
  Plano soScript({String? aviso}) => Plano(
    raiz: raiz,
    modo: Modo.script,
    movimentos: [for (final a in soltos) Movimento(a, destinoScript(a))],
    aviso: aviso,
  );
  if (modo == Modo.script) return soScript();
  final pastas = pastasSoltas(
    raiz,
    ajustes,
    protegidas: pastasDoNeatly(raiz, rodadas),
  );
  if (soltos.isEmpty && pastas.isEmpty) return soScript();
  try {
    final destinos = await (claude ?? PlanejadorClaude(regras: ajustes.regras))
        .planejar([
          ...soltos,
          ...pastas,
        ], pastasExistentes(raiz, pular: {for (final x in pastas) x.nome}));
    return Plano(
      raiz: raiz,
      modo: Modo.claude,
      movimentos: _comPastas(
        raiz,
        [for (final a in soltos) Movimento(a, destinos[a] ?? destinoScript(a))],
        pastas,
        destinos,
      ),
    );
  } on ErroClaude catch (e) {
    return soScript(aviso: '${e.mensagem} Usei o modo Script.');
  }
}

String _rel(String raiz, String caminho) =>
    p.relative(caminho, from: raiz).replaceAll(r'\', '/').toLowerCase();

/// [arquivos] mais as [pastas] que têm destino. Pasta que recebe algo (ou
/// que é o destino de outra) fica onde está.
List<Movimento> _comPastas(
  String raiz,
  List<Movimento> arquivos,
  List<ArquivoSolto> pastas,
  Map<ArquivoSolto, String> destinos,
) {
  final saindo = {
    for (final x in pastas)
      if (destinos.containsKey(x)) _rel(raiz, x.caminho): x,
  };
  for (var mudou = true; mudou;) {
    mudou = false;
    final todos = [
      ...arquivos,
      for (final x in saindo.values) Movimento(x, destinos[x]!),
    ];
    for (final m in todos) {
      final d = m.destino.toLowerCase();
      final antes = saindo.length;
      saindo.removeWhere(
        (rel, x) => x != m.arquivo && (d == rel || d.startsWith('$rel/')),
      );
      if (saindo.length != antes) mudou = true;
    }
  }
  return [
    ...arquivos,
    for (final x in saindo.values) Movimento(x, destinos[x]!),
  ];
}

/// Reorganiza a pasta toda com o Claude: além do que está solto, abre as
/// pastas de organização (por tipo, tema, origem) e redistribui o que têm
/// dentro. Unidades (projetos, programas extraídos, álbuns) vão inteiras.
/// Sem fallback para o Script: o que o Claude não decidir fica onde está.
Future<Plano> montarReorganizacao(
  String raiz,
  Ajustes ajustes, {
  PlanejadorClaude? claude,
}) async {
  final planejador = claude ?? PlanejadorClaude(regras: ajustes.regras);
  final limite = DateTime.now().subtract(
    Duration(minutes: ajustes.minutosRecentes),
  );
  bool pula(String nome) =>
      nome.startsWith('.') ||
      nome.startsWith(r'$') ||
      ignorado(nome, ajustes.ignorar);

  // Candidatas a pasta de organização: o que não é projeto, até 3 níveis.
  final candidatas = <String>[];
  void andar(Directory d, String rel, int nivel) {
    if (nivel > profundidadeMaxima || candidatas.length >= 300) return;
    final List<FileSystemEntity> filhos;
    try {
      filhos = d.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final f in filhos.whereType<Directory>()) {
      final nome = p.basename(f.path);
      if (pula(nome) || ehProjeto(f.path)) continue;
      final r = rel.isEmpty ? nome : '$rel/$nome';
      candidatas.add(r);
      andar(f, r, nivel + 1);
    }
  }

  andar(Directory(raiz), '', 1);

  try {
    final org = {
      for (final c in await planejador.classificar(raiz, candidatas))
        c.toLowerCase(),
    };
    final arquivos = [...varrer(raiz, ajustes).soltos];
    final unidades = <ArquivoSolto>[];
    final limpar = <String>[];
    void abrir(Directory d, String rel) {
      final List<FileSystemEntity> filhos;
      try {
        filhos = d.listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final f in filhos) {
        final nome = p.basename(f.path);
        if (pula(nome)) continue;
        final r = rel.isEmpty ? nome : '$rel/$nome';
        try {
          if (f is File) {
            // Os da raiz já vieram da varredura.
            if (rel.isEmpty) continue;
            final a = ArquivoSolto.de(f);
            if (!a.modificado.isAfter(limite)) arquivos.add(a);
          } else if (f is Directory) {
            final modificado = f.statSync().modified;
            if (org.contains(r.toLowerCase())) {
              limpar.add(f.path);
              abrir(f, r);
            } else if (!modificado.isAfter(limite)) {
              unidades.add(
                ArquivoSolto(
                  caminho: f.path,
                  tamanho: 0,
                  modificado: modificado,
                  pasta: true,
                ),
              );
            }
          }
        } on FileSystemException {
          continue;
        }
      }
    }

    abrir(Directory(raiz), '');
    final itens = [...arquivos, ...unidades];
    if (itens.isEmpty) {
      return Plano(raiz: raiz, modo: Modo.claude, movimentos: const []);
    }
    // As pastas que vão continuar de pé: unidades e o que não foi aberto.
    final destinos = await planejador.planejar(itens, [
      for (final c in candidatas)
        if (!org.contains(c.toLowerCase())) c,
    ], raiz: raiz);
    String onde(ArquivoSolto a) => _rel(raiz, p.dirname(a.caminho));
    return Plano(
      raiz: raiz,
      modo: Modo.claude,
      movimentos: _comPastas(
        raiz,
        [
          for (final a in arquivos)
            if (destinos[a] case final d?)
              if (d.toLowerCase() != onde(a)) Movimento(a, d),
        ],
        unidades,
        destinos,
      ),
      // Mais fundas primeiro, para a mãe ficar vazia depois.
      limpar: limpar..sort((a, b) => b.length.compareTo(a.length)),
    );
  } on ErroClaude catch (e) {
    return Plano(
      raiz: raiz,
      modo: Modo.claude,
      movimentos: const [],
      aviso: '${e.mensagem} Nada foi mexido.',
    );
  }
}

/// Refaz [plano] seguindo o [pedido] da pessoa ("junta Boletos dentro de
/// Finanças"). Item sem resposta mantém o destino que tinha. Falha do
/// Claude sobe como [ErroClaude]: o plano de antes continua valendo.
Future<Plano> ajustarPlano(
  Plano plano,
  String pedido,
  Ajustes ajustes, {
  PlanejadorClaude? claude,
}) async {
  final destinos = await (claude ?? PlanejadorClaude(regras: ajustes.regras))
      .ajustar(plano.movimentos, pedido, raiz: plano.raiz);
  final raiz = plano.raiz;
  String onde(ArquivoSolto a) => _rel(raiz, p.dirname(a.caminho));
  final pastas = [
    for (final m in plano.movimentos)
      if (m.arquivo.pasta) m.arquivo,
  ];
  return Plano(
    raiz: raiz,
    modo: Modo.claude,
    movimentos: _comPastas(
      raiz,
      [
        for (final m in plano.movimentos)
          if (!m.arquivo.pasta)
            if (destinos[m.arquivo] ?? m.destino case final d)
              // Destino igual ao lugar atual: nada a mover.
              if (d.toLowerCase() != onde(m.arquivo)) Movimento(m.arquivo, d),
      ],
      pastas,
      {
        for (final m in plano.movimentos)
          if (m.arquivo.pasta) m.arquivo: destinos[m.arquivo] ?? m.destino,
      },
    ),
    aviso: plano.aviso,
    limpar: plano.limpar,
  );
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
  // Pastas primeiro: uma que vira `Minecraft/Plugins` precisa estar no
  // lugar antes dos arquivos que vão para dentro dela.
  final ordem = [
    ...plano.movimentos.where((m) => m.arquivo.pasta),
    ...plano.movimentos.where((m) => !m.arquivo.pasta),
  ];
  for (final m in ordem) {
    final alvo = p.joinAll([plano.raiz, ...m.destino.split('/')]);
    try {
      if (m.arquivo.pasta) {
        falhas += _moverPasta(m, alvo, plano.raiz, criadas, mudancas);
        continue;
      }
      _criarPasta(alvo, plano.raiz, criadas);
      // Sumiu ou mudou desde a prévia: fica onde está.
      final origem = File(m.arquivo.caminho);
      if (!origem.existsSync()) continue;
      final para = destinoLivre(alvo, m.arquivo.nome);
      origem.renameSync(para);
      mudancas.add(Mudanca(m.arquivo.caminho, para));
    } on FileSystemException {
      falhas++;
    }
  }
  for (final d in plano.limpar) {
    try {
      final dir = Directory(d);
      if (dir.existsSync() && _soPastasVazias(dir)) {
        dir.deleteSync(recursive: true);
      }
    } on FileSystemException {
      continue;
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

/// Pasta inteira vira [alvo]. Se [alvo] já existe e é outra pasta do
/// esquema, junta o conteúdo nela, item a item, sem sobrescrever; se só
/// tem o mesmo nome (outro projeto), entra ao lado como "nome (2)".
/// Devolve quantos itens não saíram.
int _moverPasta(
  Movimento m,
  String alvo,
  String raiz,
  List<String> criadas,
  List<Mudanca> mudancas,
) {
  final origem = Directory(m.arquivo.caminho);
  if (!origem.existsSync()) return 0;
  _criarPasta(p.dirname(alvo), raiz, criadas);
  final ocupado =
      FileSystemEntity.typeSync(alvo) != FileSystemEntityType.notFound;
  if (!ocupado || !m.renomeia) {
    final para = ocupado
        ? destinoLivre(p.dirname(alvo), p.basename(alvo))
        : alvo;
    origem.renameSync(para);
    mudancas.add(Mudanca(origem.path, para));
    return 0;
  }
  var falhas = 0;
  for (final filho in origem.listSync(followLinks: false)) {
    try {
      final para = destinoLivre(alvo, p.basename(filho.path));
      filho.renameSync(para);
      mudancas.add(Mudanca(filho.path, para));
    } on FileSystemException {
      falhas++;
    }
  }
  try {
    if (origem.listSync().isEmpty) origem.deleteSync();
  } on FileSystemException {
    // Fica vazia; o desfazer volta para ela de qualquer jeito.
  }
  return falhas;
}

/// Nada além de pastas vazias (o `desktop.ini` do Windows conta como nada).
bool _soPastasVazias(Directory d) => d
    .listSync(followLinks: false)
    .every(
      (f) => f is Directory
          ? _soPastasVazias(f)
          : p.basename(f.path).toLowerCase() == 'desktop.ini',
    );

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
/// Devolve quantos itens voltaram.
int desfazer(Rodada r, Historico historico) {
  var voltaram = 0;
  for (final m in r.mudancas.reversed) {
    final FileSystemEntity f = FileSystemEntity.isDirectorySync(m.para)
        ? Directory(m.para)
        : File(m.para);
    if (!f.existsSync()) continue;
    try {
      // Pasta que foi juntada em outra sumiu: volta a existir aqui.
      Directory(p.dirname(m.de)).createSync(recursive: true);
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
