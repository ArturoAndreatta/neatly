import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'arquivo.dart';
import 'nomes.dart';
import 'plano.dart';
import 'trecho.dart';
import 'varredura.dart';

/// Modelo do modo Claude.
const modeloClaude = 'claude-haiku-5-5';

/// Arquivos por chamada: listas grandes ficam lentas e o Haiku se perde.
const _porLote = 60;

/// Lotes ao mesmo tempo: reorganizar a pasta toda são centenas de itens.
const _emParalelo = 4;

/// No ajuste cada item é só nome e destino: cabem mais por chamada.
const _porLoteAjuste = 150;

/// Nomes mandados na chamada da estrutura: o bastante para ver os temas.
const _maximoNaEstrutura = 1500;

/// Regras de gosto que vêm de fábrica. A pessoa pode trocar pelas dela nos
/// ajustes; o contrato (formato da resposta, marcas) nunca muda.
const regrasPadrao = '''
- Poucas pastas no primeiro nível: de 4 a 10, cada uma um tema amplo ("Minecraft", "Faculdade", "Finanças", "Música", "Programação", "Trabalho") ou um tipo genérico ("Imagens", "Vídeos", "Áudios", "Documentos", "Planilhas", "Instaladores", "Compactados").
- Tema acima de tipo: tudo do mesmo assunto fica sob o mesmo tema, seja qual for a extensão. Plugins .jar, mapas .zip e modpack de Minecraft vão para "Minecraft/Plugins", "Minecraft/Mapas" e "Minecraft/Modpacks", nunca "Plugins Minecraft" e "HUBs Minecraft" lado a lado no primeiro nível, nem plugin em "Instaladores".
- Nunca dois temas de primeiro nível sobre o mesmo assunto.
- Subpasta dentro do tema quando o nome ou o conteúdo diz a matéria, o cliente, o projeto ou o destino ("Faculdade/Cálculo II", "Trabalho/Cliente X") ou quando há vários itens de uma mesma espécie ("Minecraft/Plugins").
- Pasta por tipo só para o que não tem assunto claro. Capturas de tela vão para "Imagens/Capturas".
- Projetos de programação, sites e extensões vão para "Programação" com subpasta pela espécie ("Programação/Extensões Chrome", "Programação/Sites", "Programação/Projetos").
- Reaproveite as pastas que já existem quando servirem ao esquema, com o mesmo nome exato. Não crie pasta parecida com uma existente.
- Até 3 níveis. Nomes curtos, em português, com maiúscula inicial, sem data no nome (exceto ano, como "Impostos 2026").''';

/// Regras de gosto a usar: as da pessoa ou, sem elas, as de fábrica.
String regrasOuPadrao(String? regras) =>
    regras == null || regras.trim().isEmpty ? regrasPadrao : regras.trim();

// Contrato: o que o código precisa para ler a resposta. Fica fora das
// regras editáveis para nenhuma regra da pessoa quebrar o formato.

const _contratoPastas = '''
- Item com "em:" está hoje dentro daquela pasta. Responda a mesma pasta para deixá-lo onde está.
- Itens marcados [pasta] são pastas inteiras. Para elas, responda o caminho final da própria pasta, já com o nome que ela deve ter:
  - Coleção que corresponde a uma pasta do esquema vira essa pasta, sem ficar aninhada: "Plugins Minecraft" responde "Minecraft/Plugins", não "Minecraft/Plugins/Plugins Minecraft". Se a pasta já existir, o conteúdo é juntado nela.
  - Projeto ou coisa com nome próprio mantém o nome no fim: "corvo" responde "Programação/Extensões Chrome/corvo". Nome feio pode ficar limpo: "Image-Line FL Studio Producer Edition v21.0.3 Build 3517" responde "Música/Programas/FL Studio 21".
  - Itens marcados [projeto] são repositórios git ou projetos de código: o nome é o do repositório e nunca muda, nem vira pasta do esquema. Responda o tema com o nome dela no fim ("Programação/Projetos/chrome-extensions").
  - Responda "" quando ela já for uma pasta de organização da pessoa (junta coisas variadas por tipo ou tema) e deve ficar onde está.''';

const _contratoIndices =
    '- Caminhos com "/". Responda só com o JSON pedido, com todos os índices recebidos.';

/// Prompt da chamada que planeja as pastas do conjunto.
String instrucoesEstrutura(String? regras) =>
    '''
Você planeja como organizar a pasta Downloads de uma pessoa no Windows. Recebe os nomes de todos os itens soltos (arquivos e pastas soltas, estas com o começo do que têm dentro) e as pastas que já existem. Devolva a lista completa de pastas de destino (caminhos com "/") que vão receber esses itens, pensando no conjunto inteiro, não item por item.

Regras de gosto da pessoa:
${regrasOuPadrao(regras)}

Formato:
- Responda só com o JSON pedido.
''';

/// Prompt da chamada que escolhe a pasta de cada item.
String instrucoesItens(String? regras) =>
    '''
Você organiza a pasta Downloads de uma pessoa no Windows. Recebe a estrutura de pastas planejada para o conjunto todo, as pastas que já existem e uma parte dos itens soltos (nome, tamanho, data e, quando há, o começo do conteúdo). Para cada item, escolha a pasta de destino.

Regras:
- Use as pastas planejadas. Só crie outra se nenhuma servir, e então dentro de um tema planejado, seguindo as mesmas regras.
- Itens da mesma espécie vão sempre para o mesmo lugar.
$_contratoPastas

Regras de gosto da pessoa:
${regrasOuPadrao(regras)}

Formato:
$_contratoIndices
''';

/// Prompt da chamada que refaz um plano a partir de um pedido da pessoa.
String instrucoesAjuste(String? regras) =>
    '''
Você ajusta um plano para organizar a pasta Downloads de uma pessoa no Windows. Recebe o pedido da pessoa, as pastas do plano atual e uma parte dos itens, cada um com o destino que tem hoje no plano. Aplique o pedido e devolva o destino final de cada item.

Regras:
- O pedido da pessoa vale mais que as regras de gosto abaixo.
- Mude só o que o pedido pede, e o que for consequência direta dele. Os outros itens mantêm exatamente o destino atual.
- Quando o pedido acaba com uma pasta, distribua o que ela tinha pelas outras pastas do plano.
$_contratoPastas

Regras de gosto da pessoa:
${regrasOuPadrao(regras)}

Formato:
$_contratoIndices
''';

/// Itens de mentira para testar regras novas antes de salvar.
const _exemploTeste = '''
Pastas planejadas:
(nenhuma)

Pastas que já existem:
Imagens

Itens:
0. "Captura de tela 2026-10-01 101010.png" 312 KB, 2026-10-01
1. "boleto-energia-outubro.pdf" 88 KB, 2026-10-12
2. "EssentialsX-2.20.1.jar" 1.2 MB, 2026-09-03
3. "Cálculo II - Lista 3.pdf" 240 KB, 2026-10-20
4. "ChromeSetup.exe" 1.3 MB, 2026-08-30
''';

const _instrucoesClassificar = '''
Você ajuda a reorganizar a pasta Downloads de uma pessoa no Windows. Recebe as subpastas que existem, cada uma com o começo do que tem dentro. Diga quais são pastas de organização: só agrupam arquivos variados por tipo, tema ou origem ("Imagens", "Áudio/WhatsApp", "Instaladores", "Compactados", "Plugins Minecraft" com vários plugins soltos), e por isso o conteúdo pode ser redistribuído arquivo por arquivo.

As outras são unidades e vão inteiras: programa extraído com seus arquivos, álbum de fotos de um evento, projeto, pacote, jogo, curso. Na dúvida, é unidade.

Responda só com o JSON pedido: a lista dos caminhos, exatamente como recebidos, das que são de organização.
''';

const _esquemaClassificar = {
  'type': 'object',
  'properties': {
    'organizacao': {
      'type': 'array',
      'items': {'type': 'string'},
    },
  },
  'required': ['organizacao'],
};

const _esquemaEstrutura = {
  'type': 'object',
  'properties': {
    'pastas': {
      'type': 'array',
      'items': {'type': 'string'},
    },
  },
  'required': ['pastas'],
};

const _esquema = {
  'type': 'object',
  'properties': {
    'itens': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'i': {'type': 'integer'},
          'pasta': {'type': 'string'},
        },
        'required': ['i', 'pasta'],
      },
    },
  },
  'required': ['itens'],
};

/// Falha ao falar com o Claude (sem Claude Code, sem login, limite...).
class ErroClaude implements Exception {
  ErroClaude(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}

/// Roda `claude -p` com a entrada e devolve o stdout. Trocável nos testes.
typedef ExecutorClaude =
    Future<String> Function(List<String> argumentos, String entrada);

/// Caminho do Claude Code: instalador nativo, npm ou PATH. Sempre o .exe:
/// pelo `claude.cmd` o cmd.exe corta argumento com quebra de linha.
String? acharClaude() {
  final cmd = _acharLancador();
  if (cmd == null || !cmd.endsWith('.cmd')) return cmd;
  final exe = p.join(
    p.dirname(cmd),
    'node_modules',
    '@anthropic-ai',
    'claude-code',
    'bin',
    'claude.exe',
  );
  return File(exe).existsSync() ? exe : cmd;
}

String? _acharLancador() {
  final env = Platform.environment;
  final candidatos = [
    if (env['USERPROFILE'] case final u?)
      p.join(u, '.local', 'bin', 'claude.exe'),
    if (env['APPDATA'] case final a?) p.join(a, 'npm', 'claude.cmd'),
    if (env['LOCALAPPDATA'] case final l?)
      p.join(l, 'Programs', 'claude', 'claude.exe'),
  ];
  for (final c in candidatos) {
    if (File(c).existsSync()) return c;
  }
  for (final dir in (env['PATH'] ?? '').split(';')) {
    for (final nome in ['claude.exe', 'claude.cmd']) {
      final c = p.join(dir.trim(), nome);
      if (dir.trim().isNotEmpty && File(c).existsSync()) return c;
    }
  }
  return null;
}

Future<String> _executarClaude(List<String> argumentos, String entrada) async {
  final exe = acharClaude();
  if (exe == null) {
    throw ErroClaude('Claude Code não encontrado neste computador.');
  }
  // Pasta vazia: o Claude não carrega CLAUDE.md nem configuração de projeto.
  final cwd = Directory.systemTemp.createTempSync('neatly-');
  try {
    final proc = await Process.start(
      exe,
      argumentos,
      workingDirectory: cwd.path,
      runInShell: exe.endsWith('.cmd'),
    );
    proc.stdin.add(utf8.encode(entrada));
    await proc.stdin.close();
    final saida = proc.stdout.transform(utf8.decoder).join();
    final erro = proc.stderr.transform(utf8.decoder).join();
    final codigo = await proc.exitCode.timeout(
      const Duration(minutes: 3),
      onTimeout: () {
        proc.kill();
        throw ErroClaude('O Claude demorou demais para responder.');
      },
    );
    final texto = await saida;
    if (codigo != 0 && texto.trim().isEmpty) {
      throw ErroClaude(_mensagemErro(await erro));
    }
    return texto;
  } finally {
    try {
      cwd.deleteSync(recursive: true);
    } on FileSystemException {
      // Fica para o Windows limpar.
    }
  }
}

String _mensagemErro(String stderr) {
  final s = stderr.toLowerCase();
  if (s.contains('login') || s.contains('auth') || s.contains('401')) {
    return 'Entre no Claude Code (rode "claude" uma vez) para usar o modo Claude.';
  }
  if (s.contains('limit') || s.contains('429')) {
    return 'Seu limite do Claude acabou por agora.';
  }
  return 'O Claude não respondeu.';
}

/// Pede ao Claude Haiku a pasta de cada arquivo.
class PlanejadorClaude {
  /// [regras] são as regras de gosto da pessoa; null usa [regrasPadrao].
  PlanejadorClaude({ExecutorClaude? executor, this.regras})
    : _executor = executor ?? _executarClaude;

  final ExecutorClaude _executor;
  final String? regras;

  /// Roda [regras] a seco com 5 itens de exemplo. Devolve null se a
  /// resposta veio inteira, ou o motivo de não servirem.
  Future<String?> testarRegras() async {
    try {
      final resposta = await _executor(
        _argumentos(instrucoesItens(regras), _esquema),
        _exemploTeste,
      );
      final validos = {
        for (final (i, pasta) in lerResposta(resposta))
          if (i >= 0 && i < 5 && limparDestino(pasta) != null) i,
      };
      if (validos.length < 5) {
        return 'Com essas regras o Claude deixou itens sem pasta. '
            'Reescreva ou restaure o padrão.';
      }
      return null;
    } on ErroClaude catch (e) {
      return e.mensagem == 'Resposta do Claude ilegível.'
          ? 'Com essas regras a resposta do Claude veio quebrada. '
                'Reescreva ou restaure o padrão.'
          : 'Não deu para testar as regras: ${e.mensagem}';
    }
  }

  /// Refaz os destinos de [movimentos] seguindo o [pedido] da pessoa.
  /// Item sem resposta usável fica de fora: quem chama mantém o destino
  /// que ele já tinha.
  Future<Map<ArquivoSolto, String>> ajustar(
    List<Movimento> movimentos,
    String pedido, {
    required String raiz,
  }) async {
    final projetos = {
      for (final m in movimentos)
        if (m.arquivo.pasta && ehProjeto(m.arquivo.caminho)) m.arquivo,
    };
    String onde(ArquivoSolto a) =>
        p.relative(p.dirname(a.caminho), from: raiz).replaceAll(r'\', '/');
    final contagem = <String, int>{};
    for (final m in movimentos) {
      contagem[m.destino] = (contagem[m.destino] ?? 0) + 1;
    }
    final cabecalho = StringBuffer()
      ..writeln('Pedido da pessoa: ${pedido.trim()}')
      ..writeln()
      ..writeln('Pastas do plano atual:');
    for (final e in contagem.entries) {
      cabecalho.writeln('${e.key} (${e.value})');
    }
    cabecalho
      ..writeln()
      ..writeln('Itens (destino atual depois de ->):');
    final lotes = [
      for (var ini = 0; ini < movimentos.length; ini += _porLoteAjuste)
        movimentos.sublist(
          ini,
          (ini + _porLoteAjuste).clamp(0, movimentos.length),
        ),
    ];
    final saida = <ArquivoSolto, String>{};
    for (var g = 0; g < lotes.length; g += _emParalelo) {
      final grupo = lotes.sublist(g, (g + _emParalelo).clamp(0, lotes.length));
      final respostas = await Future.wait([
        for (final lote in grupo)
          _executor(_argumentos(instrucoesAjuste(regras), _esquema), () {
            final b = StringBuffer(cabecalho.toString());
            for (var i = 0; i < lote.length; i++) {
              final a = lote[i].arquivo;
              final atual = onde(a);
              final em = atual.isEmpty || atual == '.' ? '' : ', em: $atual';
              final marca = a.pasta ? '${_marca(a, projetos)} ' : '';
              b.writeln('$i. $marca"${a.nome}"$em -> ${lote[i].destino}');
            }
            return b.toString();
          }()),
      ]);
      for (var k = 0; k < grupo.length; k++) {
        final lote = grupo[k];
        for (final (i, pasta) in lerResposta(respostas[k])) {
          if (i < 0 || i >= lote.length) continue;
          var limpa = limparDestino(pasta);
          if (limpa == null) continue;
          final item = lote[i].arquivo;
          if (projetos.contains(item)) limpa = _comONome(limpa, item.nome);
          if (item.pasta) {
            final atual = _relativo(onde(item), item.nome).toLowerCase();
            final l = limpa.toLowerCase();
            if (l == atual || l.startsWith('$atual/')) continue;
          }
          saida[item] = limpa;
        }
      }
    }
    return saida;
  }

  /// Destino (pasta relativa) por item. Arquivo sem resposta usável fica
  /// de fora: quem chama decide o que fazer com ele. Pasta solta sem
  /// destino fica onde está.
  ///
  /// Com [raiz], itens de dentro das subpastas vão com o lugar atual.
  Future<Map<ArquivoSolto, String>> planejar(
    List<ArquivoSolto> itens,
    List<String> existentes, {
    String? raiz,
  }) async {
    // Primeiro o esquema do conjunto: lote a lote o Haiku não vê os temas
    // e espalha pastas soltas no primeiro nível.
    final projetos = {
      for (final a in itens)
        if (a.pasta && ehProjeto(a.caminho)) a,
    };
    String onde(ArquivoSolto a) => raiz == null
        ? ''
        : p.relative(p.dirname(a.caminho), from: raiz).replaceAll(r'\', '/');
    final conhecidas = await _estrutura(itens, existentes, projetos, onde);
    final lotes = [
      for (var ini = 0; ini < itens.length; ini += _porLote)
        itens.sublist(ini, (ini + _porLote).clamp(0, itens.length)),
    ];
    final saida = <ArquivoSolto, String>{};
    for (var g = 0; g < lotes.length; g += _emParalelo) {
      final grupo = lotes.sublist(g, (g + _emParalelo).clamp(0, lotes.length));
      final respostas = await Future.wait([
        for (final lote in grupo)
          _executor(
            _argumentos(instrucoesItens(regras), _esquema),
            _entrada(lote, conhecidas, existentes, projetos, onde),
          ),
      ]);
      for (var k = 0; k < grupo.length; k++) {
        final lote = grupo[k];
        for (final (i, pasta) in lerResposta(respostas[k])) {
          if (i < 0 || i >= lote.length) continue;
          var limpa = limparDestino(pasta);
          if (limpa == null) continue;
          final item = lote[i];
          if (projetos.contains(item)) limpa = _comONome(limpa, item.nome);
          // Pasta não entra nela mesma.
          if (item.pasta) {
            final atual = _relativo(onde(item), item.nome).toLowerCase();
            final l = limpa.toLowerCase();
            if (l == atual || l.startsWith('$atual/')) continue;
          }
          saida[item] = limpa;
          if (!conhecidas.contains(limpa)) conhecidas.add(limpa);
        }
      }
    }
    return saida;
  }

  /// Caminhos de [candidatas] (relativos, com `/`) que são pastas de
  /// organização, cujo conteúdo pode ser redistribuído.
  Future<Set<String>> classificar(String raiz, List<String> candidatas) async {
    if (candidatas.isEmpty) return {};
    final b = StringBuffer()..writeln('Pastas:');
    for (final rel in candidatas) {
      b.writeln(
        '"$rel" contém: '
        '${espiarPasta(p.joinAll([raiz, ...rel.split('/')]), maximo: 8)}',
      );
    }
    final resposta = await _executor(
      _argumentos(_instrucoesClassificar, _esquemaClassificar),
      b.toString(),
    );
    final lista = _estruturado(resposta);
    final org = lista is Map ? lista['organizacao'] : null;
    final validas = {for (final c in candidatas) c.toLowerCase(): c};
    return {
      if (org is List)
        for (final x in org.whereType<String>())
          ?validas[x.replaceAll(r'\', '/').toLowerCase()],
    };
  }

  /// Pastas planejadas para o conjunto. Resposta sem a lista não impede a
  /// rodada: os lotes decidem sozinhos.
  Future<List<String>> _estrutura(
    List<ArquivoSolto> itens,
    List<String> existentes,
    Set<ArquivoSolto> projetos,
    String Function(ArquivoSolto) onde,
  ) async {
    final passo = (itens.length / _maximoNaEstrutura).ceil().clamp(1, 1000);
    final b = StringBuffer()
      ..writeln('Pastas que já existem:')
      ..writeln(existentes.isEmpty ? '(nenhuma)' : existentes.join('\n'))
      ..writeln()
      ..writeln('Itens soltos:');
    for (var i = 0; i < itens.length; i += passo) {
      final a = itens[i];
      final nome = _relativo(onde(a), a.nome);
      b.writeln(
        a.pasta
            ? '${_marca(a, projetos)} "$nome" contém: '
                  '${espiarPasta(a.caminho, maximo: 6)}'
            : nome,
      );
    }
    final resposta = await _executor(
      _argumentos(instrucoesEstrutura(regras), _esquemaEstrutura),
      b.toString(),
    );
    final saida = <String>[];
    for (final bruta in lerEstrutura(resposta)) {
      final limpa = limparDestino(bruta);
      if (limpa != null && !saida.contains(limpa)) saida.add(limpa);
    }
    return saida;
  }

  List<String> _argumentos(String instrucoes, Map<String, Object> esquema) => [
    '-p',
    '--model',
    modeloClaude,
    '--output-format',
    'json',
    '--json-schema',
    jsonEncode(esquema),
    '--system-prompt',
    instrucoes,
    '--tools',
    '',
    '--strict-mcp-config',
    '--no-session-persistence',
  ];

  String _entrada(
    List<ArquivoSolto> lote,
    List<String> planejadas,
    List<String> existentes,
    Set<ArquivoSolto> projetos,
    String Function(ArquivoSolto) onde,
  ) {
    final b = StringBuffer()
      ..writeln('Pastas planejadas:')
      ..writeln(planejadas.isEmpty ? '(nenhuma)' : planejadas.join('\n'))
      ..writeln()
      ..writeln('Pastas que já existem:')
      ..writeln(existentes.isEmpty ? '(nenhuma)' : existentes.join('\n'))
      ..writeln()
      ..writeln('Itens:');
    for (var i = 0; i < lote.length; i++) {
      final a = lote[i];
      final data = a.modificado.toIso8601String().substring(0, 10);
      final atual = onde(a);
      final em = atual.isEmpty || atual == '.' ? '' : ', em: $atual';
      if (a.pasta) {
        b.writeln(
          '$i. ${_marca(a, projetos)} "${a.nome}", $data$em '
          '| contém: ${espiarPasta(a.caminho)}',
        );
        continue;
      }
      b.write('$i. "${a.nome}" ${_tamanho(a.tamanho)}, $data$em');
      final t = trecho(a);
      if (t != null) b.write(' | conteúdo: $t');
      b.writeln();
    }
    return b.toString();
  }
}

/// `pasta/nome`, ou só `nome` na raiz.
String _relativo(String pasta, String nome) =>
    pasta.isEmpty || pasta == '.' ? nome : '$pasta/$nome';

String _marca(ArquivoSolto a, Set<ArquivoSolto> projetos) =>
    projetos.contains(a) ? '[pasta] [projeto]' : '[pasta]';

/// [destino] terminando no nome do projeto, mesmo que o Haiku tenha
/// tentado renomear: fica dentro do tema que ele escolheu.
String _comONome(String destino, String nome) {
  final partes = destino.split('/');
  if (partes.last == nome) return destino;
  if (partes.length == profundidadeMaxima) partes.removeLast();
  return [...partes, nome].join('/');
}

/// Saída estruturada do `claude -p --output-format json --json-schema`.
Object? _estruturado(String stdout) {
  Map<String, Object?>? resultado;
  for (final linha in const LineSplitter().convert(stdout).reversed) {
    final l = linha.trim();
    if (!l.startsWith('{')) continue;
    try {
      final j = jsonDecode(l);
      if (j is Map<String, Object?> && j['type'] == 'result') {
        resultado = j;
        break;
      }
    } on FormatException {
      continue;
    }
  }
  resultado ??= () {
    try {
      return jsonDecode(stdout.trim()) as Map<String, Object?>;
    } on Object {
      return null;
    }
  }();
  if (resultado == null) throw ErroClaude('Resposta do Claude ilegível.');
  if (resultado['is_error'] == true) {
    throw ErroClaude(_mensagemErro('${resultado['result']}'));
  }
  final estruturado = resultado['structured_output'];
  if (estruturado != null || resultado['result'] is! String) {
    return estruturado;
  }
  try {
    return jsonDecode(resultado['result'] as String);
  } on FormatException {
    return null;
  }
}

/// Lê a pasta de cada índice.
List<(int, String)> lerResposta(String stdout) {
  final estruturado = _estruturado(stdout);
  final itens = estruturado is Map ? estruturado['itens'] : null;
  if (itens is! List) throw ErroClaude('Resposta do Claude ilegível.');
  return [
    for (final it in itens)
      if (it is Map && it['i'] is num && it['pasta'] is String)
        ((it['i'] as num).toInt(), it['pasta'] as String),
  ];
}

/// Lê as pastas planejadas (vazia quando a lista não vier).
List<String> lerEstrutura(String stdout) {
  final estruturado = _estruturado(stdout);
  final pastas = estruturado is Map ? estruturado['pastas'] : null;
  return pastas is List ? pastas.whereType<String>().toList() : const [];
}

String _tamanho(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).round()} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}
