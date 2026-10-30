import 'dart:convert';
import 'dart:io';

import 'package:neatly_core/neatly_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

late Directory raiz;
late Directory dados;

File criar(
  String nome, {
  String conteudo = 'x',
  Duration idade = const Duration(hours: 1),
}) {
  final f = File(p.join(raiz.path, nome))..writeAsStringSync(conteudo);
  f.setLastModifiedSync(DateTime.now().subtract(idade));
  return f;
}

String respostaClaude(List<(int, String)> itens) => jsonEncode({
  'type': 'result',
  'is_error': false,
  'structured_output': {
    'itens': [
      for (final (i, pasta) in itens) {'i': i, 'pasta': pasta},
    ],
  },
});

void main() {
  setUp(() {
    raiz = Directory.systemTemp.createTempSync('neatly-raiz-');
    dados = Directory.systemTemp.createTempSync('neatly-dados-');
  });
  tearDown(() {
    raiz.deleteSync(recursive: true);
    dados.deleteSync(recursive: true);
  });

  group('varredura', () {
    test('pula segredos, downloads em andamento, recentes e subpastas', () {
      criar('foto.png');
      criar('.env');
      criar('chave.pem');
      criar('filme.mp4.crdownload');
      criar('novo.pdf', idade: Duration.zero);
      Directory(p.join(raiz.path, 'Projetos')).createSync();
      final v = varrer(raiz.path, const Ajustes());
      expect(v.soltos.map((a) => a.nome), ['foto.png']);
      expect(v.recentes, 1);
    });
  });

  group('regras do Script', () {
    String destino(String nome) => destinoScript(
      ArquivoSolto(caminho: nome, tamanho: 1, modificado: DateTime(2026)),
    );

    test('extensão e padrões de nome', () {
      expect(destino('Screenshot 2026-10-30.png'), 'Imagens/Capturas');
      expect(destino('WhatsApp Video 2026.mp4'), 'Vídeos/WhatsApp');
      expect(destino('boleto-condominio.pdf'), 'Documentos/Finanças');
      expect(destino('FlutterSetup.exe'), 'Instaladores');
      expect(destino('relatorio.XLSX'), 'Planilhas');
      expect(destino('semextensao'), 'Outros');
      expect(destino('fatura.exe'), 'Instaladores');
    });
  });

  group('nomes vindos do Claude', () {
    test('sem fuga da pasta nem caractere proibido', () {
      expect(limparDestino('../../Windows/System32'), 'Windows/System32');
      expect(limparDestino(r'C:\Users\x'), 'C/Users/x');
      expect(limparDestino('Faculdade/Cálculo II/'), 'Faculdade/Cálculo II');
      expect(limparDestino('A/B/C/D/E'), 'A/B/C');
      expect(limparDestino('con'), '_con');
      expect(limparDestino('Notas: "boas"?.'), 'Notas boas');
      expect(limparDestino(' / .. / '), isNull);
    });
  });

  group('organizar e desfazer', () {
    test(
      'move sem sobrescrever e desfaz tudo, apagando pastas vazias',
      () async {
        criar('a.png', conteudo: 'novo');
        Directory(p.join(raiz.path, 'Imagens')).createSync();
        File(p.join(raiz.path, 'Imagens', 'a.png')).writeAsStringSync('velho');
        criar('b.zip');
        final hist = Historico(dados.path);

        final plano = await montarPlano(
          raiz.path,
          const Ajustes(),
          Modo.script,
        );
        final r = aplicar(plano, hist);
        expect(r.mudancas, hasLength(2));
        expect(
          File(p.join(raiz.path, 'Imagens', 'a.png')).readAsStringSync(),
          'velho',
        );
        expect(
          File(p.join(raiz.path, 'Imagens', 'a (2).png')).readAsStringSync(),
          'novo',
        );
        expect(r.pastasCriadas, [p.join(raiz.path, 'Compactados')]);
        expect(hist.carregar().single.id, r.id);

        expect(desfazer(r, hist), 2);
        expect(File(p.join(raiz.path, 'a.png')).readAsStringSync(), 'novo');
        expect(File(p.join(raiz.path, 'b.zip')).existsSync(), isTrue);
        expect(
          Directory(p.join(raiz.path, 'Compactados')).existsSync(),
          isFalse,
        );
        expect(Directory(p.join(raiz.path, 'Imagens')).existsSync(), isTrue);
        expect(hist.carregar().single.desfeita, isTrue);
      },
    );

    test(
      'modo Claude usa as pastas do Claude e o Script no que faltar',
      () async {
        criar('lista-derivadas.txt', conteudo: 'Lista 3 de Cálculo II');
        criar('foto.jpg');
        String? entrada;
        final claude = PlanejadorClaude(
          executor: (args, e) async {
            entrada = e;
            return respostaClaude([(1, 'Faculdade/Cálculo II'), (5, 'Nada')]);
          },
        );
        final plano = await montarPlano(
          raiz.path,
          const Ajustes(),
          Modo.claude,
          claude: claude,
        );
        expect(plano.modo, Modo.claude);
        final destinos = {
          for (final m in plano.movimentos) m.arquivo.nome: m.destino,
        };
        expect(destinos, {
          'foto.jpg': 'Imagens',
          'lista-derivadas.txt': 'Faculdade/Cálculo II',
        });
        expect(entrada, contains('Lista 3 de Cálculo II'));
      },
    );

    test('Claude falhando cai no Script com aviso', () async {
      criar('foto.jpg');
      final claude = PlanejadorClaude(
        executor: (args, e) async => throw ErroClaude('Sem login.'),
      );
      final plano = await montarPlano(
        raiz.path,
        const Ajustes(),
        Modo.claude,
        claude: claude,
      );
      expect(plano.modo, Modo.script);
      expect(plano.aviso, contains('Sem login.'));
      expect(plano.movimentos.single.destino, 'Imagens');
    });

    test('árvore da prévia marca pastas novas', () async {
      Directory(p.join(raiz.path, 'Imagens')).createSync();
      criar('Screenshot 1.png');
      criar('c.png');
      final plano = await montarPlano(raiz.path, const Ajustes(), Modo.script);
      final arvore = plano.arvore(
        (rel) =>
            Directory(p.joinAll([raiz.path, ...rel.split('/')])).existsSync(),
      );
      final imagens = arvore.single;
      expect(imagens.nova, isFalse);
      expect(imagens.total, 2);
      expect(imagens.filhas['Capturas']!.nova, isTrue);
    });
  });

  group('resposta do Claude', () {
    test('lê structured_output, result em texto e erro', () {
      expect(lerResposta(respostaClaude([(0, 'X')])), [(0, 'X')]);
      expect(
        lerResposta(
          jsonEncode({
            'type': 'result',
            'result': '{"itens":[{"i":1,"pasta":"Y"}]}',
          }),
        ),
        [(1, 'Y')],
      );
      expect(
        () => lerResposta(
          jsonEncode({
            'type': 'result',
            'is_error': true,
            'result': 'rate limit',
          }),
        ),
        throwsA(isA<ErroClaude>()),
      );
      expect(() => lerResposta('lixo'), throwsA(isA<ErroClaude>()));
    });
  });

  group('ajustes, agendamento e versão', () {
    test('salva e carrega', () {
      const Ajustes(
        modo: Modo.script,
        agendamento: Agendamento(hora: 21, minuto: 5),
      ).salvar(dados.path);
      final a = Ajustes.carregar(dados.path);
      expect(a.modo, Modo.script);
      expect(a.agendamento.horario, '21:05');
    });

    test('XML da tarefa roda quando o PC ligar', () {
      final xml = xmlTarefa(
        const Agendamento(hora: 7, minuto: 30),
        r'C:\A & B\neatly.exe',
      );
      expect(xml, contains('T07:30:00'));
      expect(xml, contains('<StartWhenAvailable>true</StartWhenAvailable>'));
      expect(xml, contains(r'C:\A &amp; B\neatly.exe'));
      expect(xml, contains('--agendado'));
    });

    test('compara versões', () {
      expect(compararVersoes('v2.1.0', '2.0.9'), 1);
      expect(compararVersoes('2.0.0', 'v2.0.0'), 0);
      expect(compararVersoes('1.9', '2.0.0'), -1);
    });

    test('migra o Neatly 1', () {
      File(
        p.join(dados.path, 'config.json'),
      ).writeAsStringSync('\uFEFF{"modo":"claude"}');
      File(p.join(dados.path, 'organizar.ps1')).writeAsStringSync('');
      File(p.join(dados.path, 'historico.jsonl')).writeAsStringSync('{}');
      final a = migrarV1(dados.path, mexerNoWindows: false)!;
      expect(a.modo, Modo.claude);
      expect(File(p.join(dados.path, 'organizar.ps1')).existsSync(), isFalse);
      expect(
        File(p.join(dados.path, 'historico-v1.jsonl')).existsSync(),
        isTrue,
      );
      expect(migrarV1(dados.path, mexerNoWindows: false), isNull);
    });
  });
}
