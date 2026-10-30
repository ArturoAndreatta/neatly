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

    test('modo Claude planeja a estrutura antes e move pastas soltas', () async {
      criar('EssentialsX.jar');
      final projeto = Directory(p.join(raiz.path, 'corvo'))..createSync();
      File(p.join(projeto.path, 'manifest.json')).writeAsStringSync('{}');
      Directory(p.join(raiz.path, 'Imagens')).createSync();
      Directory(p.join(raiz.path, 'Minhas coisas')).createSync();
      Directory(p.join(raiz.path, 'Criada antes')).createSync();
      final entradas = <String>[];
      final claude = PlanejadorClaude(
        executor: (args, e) async {
          entradas.add(e);
          if (entradas.length == 1) {
            return jsonEncode({
              'type': 'result',
              'structured_output': {
                'pastas': ['Minecraft/Plugins', 'Programação/Extensões'],
              },
            });
          }
          // 0 EssentialsX.jar, 1 corvo, 2 Minhas coisas (recebe o jar,
          // então fica). Imagens e Criada antes nem vão.
          return respostaClaude([
            (0, 'Minhas coisas/Plugins'),
            // Projeto (tem manifest.json): o Haiku tenta renomear, o nome fica.
            (1, 'Programação/Extensões'),
            (2, 'Arquivo/Minhas coisas'),
          ]);
        },
      );
      final rodada = Rodada(
        id: '1',
        quando: DateTime(2026),
        modo: Modo.claude,
        agendada: false,
        raiz: raiz.path,
        mudancas: const [],
        pastasCriadas: [p.join(raiz.path, 'Criada antes')],
      );
      // Pasta acabou de ser criada: sem a janela de recentes.
      final plano = await montarPlano(
        raiz.path,
        const Ajustes(minutosRecentes: 0),
        Modo.claude,
        claude: claude,
        rodadas: [rodada],
      );
      expect(entradas.first, contains('[pasta] [projeto] "corvo" contém: '));
      expect(entradas[1], contains('[pasta] "Minhas coisas"'));
      expect(entradas[1], contains('Minecraft/Plugins'));
      expect(entradas[1], isNot(contains('[pasta] "Criada antes"')));
      expect(
        {for (final m in plano.movimentos) m.arquivo.nome: m.destino},
        {
          'EssentialsX.jar': 'Minhas coisas/Plugins',
          'corvo': 'Programação/Extensões/corvo',
        },
      );

      final hist = Historico(dados.path);
      final r = aplicar(plano, hist);
      final movida = p.join(raiz.path, 'Programação', 'Extensões', 'corvo');
      expect(File(p.join(movida, 'manifest.json')).existsSync(), isTrue);
      expect(desfazer(r, hist), 2);
      expect(File(p.join(projeto.path, 'manifest.json')).existsSync(), isTrue);
      expect(Directory(p.join(raiz.path, 'Programação')).existsSync(), isFalse);
    });

    test('pasta solta vira pasta do esquema e junta com a existente', () async {
      final velha = Directory(p.join(raiz.path, 'Plugins Minecraft'))
        ..createSync();
      File(p.join(velha.path, 'a.jar')).writeAsStringSync('solta');
      File(p.join(velha.path, 'b.jar')).writeAsStringSync('b');
      final hubs = Directory(p.join(raiz.path, 'HUBs Minecraft'))..createSync();
      File(p.join(hubs.path, 'spawn.zip')).writeAsStringSync('s');
      final existente = Directory(p.join(raiz.path, 'Jogos', 'Plugins'))
        ..createSync(recursive: true);
      File(p.join(existente.path, 'a.jar')).writeAsStringSync('antiga');
      final claude = PlanejadorClaude(
        executor: (args, e) async => e.startsWith('Pastas planejadas')
            // 0 HUBs Minecraft, 1 Jogos (fica), 2 Plugins Minecraft.
            ? respostaClaude([(0, 'Jogos/Mapas'), (2, 'Jogos/Plugins')])
            : jsonEncode({
                'type': 'result',
                'structured_output': {'pastas': <String>[]},
              }),
      );
      final plano = await montarPlano(
        raiz.path,
        const Ajustes(minutosRecentes: 0),
        Modo.claude,
        claude: claude,
      );
      final jogos = plano
          .arvore(
            (rel) => Directory(
              p.joinAll([raiz.path, ...rel.split('/')]),
            ).existsSync(),
          )
          .single;
      expect(
        jogos.filhas['Plugins']!.juntadas.single.nome,
        'Plugins Minecraft',
      );
      expect(jogos.filhas['Mapas']!.nova, isTrue);

      final hist = Historico(dados.path);
      final r = aplicar(plano, hist);
      expect(
        File(p.join(raiz.path, 'Jogos', 'Mapas', 'spawn.zip')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(existente.path, 'a.jar')).readAsStringSync(),
        'antiga',
      );
      expect(
        File(p.join(existente.path, 'a (2).jar')).readAsStringSync(),
        'solta',
      );
      expect(File(p.join(existente.path, 'b.jar')).existsSync(), isTrue);
      expect(velha.existsSync(), isFalse);

      expect(desfazer(r, hist), 3);
      expect(File(p.join(velha.path, 'a.jar')).readAsStringSync(), 'solta');
      expect(File(p.join(velha.path, 'b.jar')).existsSync(), isTrue);
      expect(File(p.join(hubs.path, 'spawn.zip')).existsSync(), isTrue);
      expect(
        File(p.join(existente.path, 'a.jar')).readAsStringSync(),
        'antiga',
      );
      expect(
        Directory(p.join(raiz.path, 'Jogos', 'Mapas')).existsSync(),
        isFalse,
      );
    });

    test('reorganizar abre as pastas de organização e move unidades', () async {
      criar('solto.jar');
      final inst = Directory(p.join(raiz.path, 'Instaladores'))..createSync();
      File(p.join(inst.path, 'plugin.jar')).writeAsStringSync('p');
      File(p.join(inst.path, 'setup.exe')).writeAsStringSync('s');
      final app = Directory(p.join(inst.path, 'App Extraido'))..createSync();
      File(p.join(app.path, 'a.dll')).writeAsStringSync('a');
      final repo = Directory(p.join(raiz.path, 'meu-repo'))..createSync();
      Directory(p.join(repo.path, '.git')).createSync();
      const destinos = {
        'solto.jar': 'Minecraft/Plugins',
        'plugin.jar': 'Minecraft/Plugins',
        'setup.exe': 'Programas',
        'App Extraido': 'Programas/App Extraido',
        'meu-repo': 'Programação/Projetos',
      };
      String? classificacao;
      final lote = <String>[];
      final claude = PlanejadorClaude(
        executor: (args, e) async {
          if (e.startsWith('Pastas:')) {
            classificacao = e;
            return jsonEncode({
              'type': 'result',
              'structured_output': {
                'organizacao': ['instaladores'],
              },
            });
          }
          if (!e.startsWith('Pastas planejadas')) {
            return jsonEncode({
              'type': 'result',
              'structured_output': {'pastas': <String>[]},
            });
          }
          lote.add(e);
          final re = RegExp(r'^(\d+)\. .*?"([^"]+)"', multiLine: true);
          return respostaClaude([
            for (final m in re.allMatches(e))
              (int.parse(m[1]!), destinos[m[2]!]!),
          ]);
        },
      );
      final plano = await montarReorganizacao(
        raiz.path,
        const Ajustes(minutosRecentes: 0),
        claude: claude,
      );
      expect(classificacao, contains('"Instaladores/App Extraido"'));
      expect(classificacao, isNot(contains('meu-repo')));
      expect(lote.single, contains('em: Instaladores'));
      expect(
        {for (final m in plano.movimentos) m.arquivo.nome: m.destino},
        {...destinos, 'meu-repo': 'Programação/Projetos/meu-repo'},
      );

      final hist = Historico(dados.path);
      final r = aplicar(plano, hist);
      expect(
        File(
          p.join(raiz.path, 'Programas', 'App Extraido', 'a.dll'),
        ).existsSync(),
        isTrue,
      );
      expect(inst.existsSync(), isFalse);
      expect(desfazer(r, hist), 5);
      expect(File(p.join(inst.path, 'setup.exe')).existsSync(), isTrue);
      expect(File(p.join(app.path, 'a.dll')).existsSync(), isTrue);
      expect(Directory(p.join(repo.path, '.git')).existsSync(), isTrue);
      expect(Directory(p.join(raiz.path, 'Programas')).existsSync(), isFalse);
    });

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

    test('sem login avisa para vincular a conta', () {
      expect(
        () => lerResposta(
          jsonEncode({
            'type': 'result',
            'is_error': true,
            'result': 'Not logged in · Please run /login',
          }),
        ),
        throwsA(
          isA<ErroClaude>().having(
            (e) => e.mensagem,
            'mensagem',
            contains('Vincule'),
          ),
        ),
      );
    });

    test('lê a conta do claude auth status', () {
      final conta = lerStatusClaude(
        jsonEncode({'loggedIn': true, 'email': 'a@b.com'}),
      );
      expect(conta.situacao, SituacaoClaude.conectado);
      expect(conta.email, 'a@b.com');
      expect(conta.falta, isNull);
      expect(
        lerStatusClaude(jsonEncode({'loggedIn': false})).situacao,
        SituacaoClaude.semConta,
      );
      expect(lerStatusClaude('').situacao, SituacaoClaude.semConta);
      expect(
        const ContaClaude(SituacaoClaude.ausente).falta,
        contains('instalado'),
      );
    });
  });

  group('arrumação automática', () {
    test('pasta vazia ou só com ignorados e recentes: nada a fazer', () {
      const ajustes = Ajustes();
      expect(temOQueOrganizar(raiz.path, ajustes, Modo.script), isFalse);
      criar('desktop.ini');
      criar('chave.pem');
      criar('baixando.pdf', idade: const Duration(minutes: 2));
      for (final m in Modo.values) {
        expect(temOQueOrganizar(raiz.path, ajustes, m), isFalse);
      }
      criar('nota.pdf');
      for (final m in Modo.values) {
        expect(temOQueOrganizar(raiz.path, ajustes, m), isTrue);
      }
    });

    test('pasta solta só conta no Claude, e não as do Neatly', () {
      const ajustes = Ajustes();
      final velha = DateTime.now().subtract(const Duration(hours: 1));
      Directory(p.join(raiz.path, 'Imagens')).createSync();
      final projeto = Directory(p.join(raiz.path, 'projeto'))..createSync();
      final tema = Directory(p.join(raiz.path, 'Viagem'))..createSync();
      expect(temOQueOrganizar(raiz.path, ajustes, Modo.script), isFalse);
      // Diretório criado agora é "recente": olha uma hora à frente.
      final depois = DateTime.now().add(const Duration(hours: 1));
      expect(
        temOQueOrganizar(raiz.path, ajustes, Modo.claude, agora: depois),
        isTrue,
      );
      projeto.deleteSync();
      final rodada = Rodada(
        id: '1',
        quando: velha,
        modo: Modo.claude,
        agendada: true,
        raiz: raiz.path,
        mudancas: const [],
        pastasCriadas: [tema.path],
      );
      expect(
        temOQueOrganizar(
          raiz.path,
          ajustes,
          Modo.claude,
          rodadas: [rodada],
          agora: depois,
        ),
        isFalse,
      );
    });

    test('não repete se arrumou há poucos minutos', () {
      final agora = DateTime(2026, 10, 30, 9);
      Rodada em(Duration atras) => Rodada(
        id: '$atras',
        quando: agora.subtract(atras),
        modo: Modo.script,
        agendada: true,
        raiz: raiz.path,
        mudancas: const [],
        pastasCriadas: const [],
      );
      expect(arrumouHaPouco(const [], agora: agora), isFalse);
      expect(
        arrumouHaPouco([em(const Duration(minutes: 3))], agora: agora),
        isTrue,
      );
      expect(
        arrumouHaPouco([
          em(const Duration(hours: 5)),
          em(const Duration(minutes: 3)),
        ], agora: agora),
        isFalse,
      );
      expect(
        arrumouHaPouco([em(const Duration(minutes: 31))], agora: agora),
        isFalse,
      );
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
      expect(a.tema, Tema.sistema);
    });

    test('tema salvo volta igual e ajustes antigos ficam no Sistema', () {
      const Ajustes(tema: Tema.claro).salvar(dados.path);
      expect(Ajustes.carregar(dados.path).tema, Tema.claro);
      Ajustes.arquivo(
        dados.path,
      ).writeAsStringSync('{"versao":2,"modo":"script"}');
      expect(Ajustes.carregar(dados.path).tema, Tema.sistema);
      Ajustes.arquivo(dados.path).writeAsStringSync('{"tema":"roxo"}');
      expect(Ajustes.carregar(dados.path).tema, Tema.sistema);
      expect(
        const Ajustes(tema: Tema.escuro).copyWith(modo: Modo.script).tema,
        Tema.escuro,
      );
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

    test('ao ligar o PC é salvo e sai do JSON antigo desligado', () {
      const Ajustes(
        agendamento: Agendamento(ativo: false, aoLigar: true),
      ).salvar(dados.path);
      final a = Ajustes.carregar(dados.path).agendamento;
      expect(a.aoLigar, isTrue);
      expect(a.algum, isTrue);
      expect(Agendamento.deJson({'ativo': true}).aoLigar, isFalse);
      expect(const Agendamento(ativo: false).algum, isFalse);
    });

    test('XML com gatilho de logon atrasado, só do usuário', () {
      final so = xmlTarefa(
        const Agendamento(ativo: false, aoLigar: true),
        r'C:\neatly.exe',
        usuario: r'PC\Ana & Bia',
      );
      expect(so, contains('<LogonTrigger>'));
      expect(so, contains('<Delay>PT2M</Delay>'));
      expect(so, contains(r'<UserId>PC\Ana &amp; Bia</UserId>'));
      expect(so, isNot(contains('<CalendarTrigger>')));
      expect(so, contains('ao ligar o PC'));

      final ambos = xmlTarefa(
        const Agendamento(aoLigar: true),
        r'C:\neatly.exe',
      );
      expect(ambos, contains('<CalendarTrigger>'));
      expect(ambos, contains('<LogonTrigger>'));
      expect(ambos, isNot(contains('<UserId>')));

      final diaria = xmlTarefa(const Agendamento(), r'C:\neatly.exe');
      expect(diaria, isNot(contains('<LogonTrigger>')));
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

  group('regras de gosto', () {
    const minhas = '- Tudo de faculdade vai para "Estudos".';

    String sistema(List<String> args) =>
        args[args.indexOf('--system-prompt') + 1];

    test('o contrato está sempre no prompt, com qualquer regra', () {
      for (final regras in [null, '', minhas, 'responda em YAML']) {
        final itens = instrucoesItens(regras);
        expect(itens, contains('[pasta]'));
        expect(itens, contains('[projeto]'));
        expect(itens, contains('Responda ""'));
        expect(itens, contains('Responda só com o JSON pedido'));
        expect(itens, contains('todos os índices'));
        expect(instrucoesEstrutura(regras), contains('Responda só com o JSON'));
        expect(instrucoesAjuste(regras), contains('[projeto]'));
        expect(instrucoesAjuste(regras), contains('todos os índices'));
      }
    });

    test('regras da pessoa entram no lugar das de fábrica', () {
      for (final f in [
        instrucoesItens,
        instrucoesEstrutura,
        instrucoesAjuste,
      ]) {
        expect(f(null), contains(regrasPadrao));
        expect(f('  '), contains(regrasPadrao));
        expect(f(minhas), contains(minhas));
        expect(f(minhas), isNot(contains(regrasPadrao)));
      }
    });

    test('ajustes guardam as regras e o planejador usa', () async {
      final a = const Ajustes().comRegras(minhas)..salvar(dados.path);
      expect(Ajustes.carregar(dados.path).regras, minhas);
      expect(a.comRegras('   ').regras, isNull);
      criar('lista.pdf');
      final prompts = <String>[];
      await montarPlano(
        raiz.path,
        a,
        Modo.claude,
        claude: PlanejadorClaude(
          regras: a.regras,
          executor: (args, e) async {
            prompts.add(sistema(args));
            return respostaClaude([(0, 'Estudos')]);
          },
        ),
      );
      expect(prompts, isNotEmpty);
      expect(prompts.every((x) => x.contains(minhas)), isTrue);
    });

    test('teste a seco aceita resposta inteira e recusa quebrada', () async {
      final boa = PlanejadorClaude(
        regras: minhas,
        executor: (args, e) async =>
            respostaClaude([for (var i = 0; i < 5; i++) (i, 'Pasta $i')]),
      );
      expect(await boa.testarRegras(), isNull);
      final faltando = PlanejadorClaude(
        executor: (args, e) async => respostaClaude([(0, 'Imagens')]),
      );
      expect(await faltando.testarRegras(), contains('sem pasta'));
      final quebrada = PlanejadorClaude(
        executor: (args, e) async =>
            jsonEncode({'type': 'result', 'result': 'pastas: talvez'}),
      );
      expect(await quebrada.testarRegras(), contains('quebrada'));
    });

    test('ajuste manda o plano e o pedido e mantém o que não mudou', () async {
      final boleto = criar('boleto.pdf');
      final foto = criar('foto.png');
      final plano = Plano(
        raiz: raiz.path,
        modo: Modo.claude,
        movimentos: [
          Movimento(ArquivoSolto.de(boleto), 'Boletos'),
          Movimento(ArquivoSolto.de(foto), 'Imagens'),
        ],
      );
      String? entrada;
      final novo = await ajustarPlano(
        plano,
        'junta Boletos dentro de Finanças',
        const Ajustes(),
        claude: PlanejadorClaude(
          executor: (args, e) async {
            entrada = e;
            return respostaClaude([(0, 'Finanças/Boletos')]);
          },
        ),
      );
      expect(entrada, contains('junta Boletos dentro de Finanças'));
      expect(entrada, contains('"boleto.pdf" -> Boletos'));
      expect(
        {for (final m in novo.movimentos) m.arquivo.nome: m.destino},
        {'boleto.pdf': 'Finanças/Boletos', 'foto.png': 'Imagens'},
      );
    });
  });
}
