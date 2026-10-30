import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'arquivo.dart';
import 'nomes.dart';
import 'trecho.dart';

/// Modelo do modo Claude.
const modeloClaude = 'claude-haiku-5-5';

/// Arquivos por chamada: listas grandes ficam lentas e o Haiku se perde.
const _porLote = 60;

const _instrucoes = '''
Você organiza a pasta Downloads de uma pessoa no Windows. Recebe uma lista de arquivos (nome, tamanho, data e, quando há, o começo do conteúdo) e as pastas que já existem. Para cada arquivo, escolha a pasta de destino.

Regras:
- Agrupe por assunto ou propósito quando der para perceber, do tema amplo para o específico: "Faculdade/Cálculo II", "Faculdade/TCC", "Finanças/Boletos", "Trabalho/Cliente X", "Viagens/Florianópolis". Seja específico: se o nome ou o conteúdo diz a matéria, o cliente, o destino ou o projeto, crie a subpasta com esse nome.
- Use pastas genéricas por tipo ("Imagens", "Instaladores", "Vídeos", "Compactados") quando o arquivo não tiver assunto claro.
- Reaproveite as pastas que já existem quando servirem, com o mesmo nome exato. Não crie pasta parecida com uma existente.
- Até 3 níveis. Nomes curtos, em português, com maiúscula inicial, sem data no nome da pasta (exceto ano, como "Impostos 2026").
- Subpasta específica com um arquivo só é bem-vinda ("Faculdade/TCC"); o que evitar é pasta de primeiro nível nova para um arquivo avulso sem assunto.
- Capturas de tela vão para "Imagens/Capturas".
- Responda só com o JSON pedido, com todos os índices recebidos.
''';

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
  PlanejadorClaude({ExecutorClaude? executor})
    : _executor = executor ?? _executarClaude;

  final ExecutorClaude _executor;

  /// Destino (pasta relativa) por arquivo. Arquivo sem resposta usável
  /// fica de fora: quem chama decide o que fazer com ele.
  Future<Map<ArquivoSolto, String>> planejar(
    List<ArquivoSolto> arquivos,
    List<String> existentes,
  ) async {
    final saida = <ArquivoSolto, String>{};
    final conhecidas = [...existentes];
    for (var ini = 0; ini < arquivos.length; ini += _porLote) {
      final lote = arquivos.sublist(
        ini,
        (ini + _porLote).clamp(0, arquivos.length),
      );
      final resposta = await _executor(
        _argumentos(),
        _entrada(lote, conhecidas),
      );
      for (final (i, pasta) in lerResposta(resposta)) {
        if (i < 0 || i >= lote.length) continue;
        final limpa = limparDestino(pasta);
        if (limpa == null) continue;
        saida[lote[i]] = limpa;
        if (!conhecidas.contains(limpa)) conhecidas.add(limpa);
      }
    }
    return saida;
  }

  List<String> _argumentos() => [
    '-p',
    '--model',
    modeloClaude,
    '--output-format',
    'json',
    '--json-schema',
    jsonEncode(_esquema),
    '--system-prompt',
    _instrucoes,
    '--tools',
    '',
    '--strict-mcp-config',
    '--no-session-persistence',
  ];

  String _entrada(List<ArquivoSolto> lote, List<String> existentes) {
    final b = StringBuffer()
      ..writeln('Pastas que já existem:')
      ..writeln(existentes.isEmpty ? '(nenhuma)' : existentes.join('\n'))
      ..writeln()
      ..writeln('Arquivos:');
    for (var i = 0; i < lote.length; i++) {
      final a = lote[i];
      b.write(
        '$i. "${a.nome}" ${_tamanho(a.tamanho)}, '
        '${a.modificado.toIso8601String().substring(0, 10)}',
      );
      final t = trecho(a);
      if (t != null) b.write(' | conteúdo: $t');
      b.writeln();
    }
    return b.toString();
  }
}

/// Lê o JSON do `claude -p --output-format json --json-schema`.
List<(int, String)> lerResposta(String stdout) {
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
  var estruturado = resultado['structured_output'];
  if (estruturado == null && resultado['result'] is String) {
    try {
      estruturado = jsonDecode(resultado['result'] as String);
    } on FormatException {
      estruturado = null;
    }
  }
  final itens = estruturado is Map ? estruturado['itens'] : null;
  if (itens is! List) throw ErroClaude('Resposta do Claude ilegível.');
  return [
    for (final it in itens)
      if (it is Map && it['i'] is num && it['pasta'] is String)
        ((it['i'] as num).toInt(), it['pasta'] as String),
  ];
}

String _tamanho(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).round()} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}
