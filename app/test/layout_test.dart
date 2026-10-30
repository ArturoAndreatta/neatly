import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatly/estado.dart';
import 'package:neatly/tema.dart';
import 'package:neatly/ui/app.dart';
import 'package:neatly/ui/barra.dart';
import 'package:neatly_core/neatly_core.dart';
import 'package:path/path.dart' as p;

/// Cada tela e estado no tamanho mínimo da janela (e em maiores): nada pode
/// estourar. Com `NEATLY_FOTOS=pasta`, salva um PNG de cada um com as fontes
/// do Windows, para conferir a olho.
const _tamanhos = [Size(420, 560), Size(460, 640), Size(900, 720)];

final _fotos = Platform.environment['NEATLY_FOTOS'];

Future<void> _carregarFontes() async {
  Future<void> fonte(String familia, String arquivo) async {
    final f = File(arquivo);
    if (!f.existsSync()) return;
    final bytes = f.readAsBytesSync();
    await (FontLoader(
      familia,
    )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
  }

  const fontes = r'C:\Windows\Fonts';
  await fonte(fonteTexto, p.join(fontes, 'SegUIVar.ttf'));
  await fonte(fonteDisplay, p.join(fontes, 'SegUIVar.ttf'));
  await fonte('Segoe UI', p.join(fontes, 'segoeui.ttf'));
  final flutter = Platform.environment['FLUTTER_ROOT'] ?? '';
  await fonte(
    'MaterialIcons',
    p.join(
      flutter,
      'bin',
      'cache',
      'artifacts',
      'material_fonts',
      'MaterialIcons-Regular.otf',
    ),
  );
}

/// Arquivo antigo: os baixados agora ficam para depois.
void _velho(String caminho) => File(caminho)
  ..writeAsStringSync('x')
  ..setLastModifiedSync(DateTime(2026));

typedef _Preparo = void Function(Estado e, Directory pasta);

ArquivoSolto _solto(Directory pasta, String nome, {bool ePasta = false}) =>
    ArquivoSolto(
      caminho: p.join(pasta.path, nome),
      tamanho: 1000,
      modificado: DateTime(2026, 10, 1),
      pasta: ePasta,
    );

Plano _planoGrande(Directory pasta) => Plano(
  raiz: pasta.path,
  modo: Modo.claude,
  aviso:
      'O Claude não respondeu a tempo para 12 arquivos; eles foram '
      'separados por tipo.',
  movimentos: [
    for (var i = 0; i < 180; i++)
      Movimento(
        _solto(
          pasta,
          'Relatório trimestral de despesas do departamento financeiro $i.pdf',
        ),
        'Faculdade de Engenharia Mecânica/Disciplina com nome longo ${i % 14}'
        '${i.isEven ? '/Provas antigas resolvidas' : ''}',
      ),
    Movimento(_solto(pasta, 'Minecraft', ePasta: true), 'Jogos/Minecraft'),
  ],
);

List<Rodada> _rodadas(Directory pasta) => [
  for (var i = 0; i < 12; i++)
    Rodada(
      id: '$i',
      quando: DateTime.now().subtract(Duration(days: i, hours: 2)),
      modo: i.isEven ? Modo.claude : Modo.script,
      agendada: i % 3 == 0,
      raiz: pasta.path,
      falhas: i == 1 ? 3 : 0,
      desfeita: i == 2,
      mudancas: [
        for (var j = 0; j < 40 - i; j++)
          Mudanca(
            p.join(pasta.path, 'arquivo com nome bem comprido número $j.docx'),
            p.join(
              pasta.path,
              'Documentos de trabalho ${j % 5}',
              'Subpasta ${j % 3}',
              'arquivo com nome bem comprido número $j.docx',
            ),
          ),
      ],
      pastasCriadas: const [],
    ),
];

final _cenarios = <String, (_Preparo, Future<void> Function(WidgetTester)?)>{
  'inicio-vazio': ((e, d) {}, null),
  'inicio-arquivos': (
    (e, d) {
      for (var i = 0; i < 37; i++) {
        _velho(p.join(d.path, 'arquivo $i.pdf'));
      }
      e.olhar();
    },
    null,
  ),
  'inicio-aviso': (
    (e, d) {
      _velho(p.join(d.path, 'um.pdf'));
      e.olhar();
      e.aviso =
          'O Claude não respondeu agora. Tente de novo em alguns minutos ou '
          'use o modo Script.';
    },
    null,
  ),
  'repensando-menu': (
    (e, d) {
      e.fase = Fase.planejando;
      e.reorganizando = true;
    },
    (t) => t.tap(find.byType(SeletorModo)),
  ),
  'lendo': (
    (e, d) {
      _velho(p.join(d.path, 'um.pdf'));
      e.olhar();
      e.fase = Fase.planejando;
    },
    null,
  ),
  'previa-grande': (
    (e, d) {
      e.plano = _planoGrande(d);
      e.fase = Fase.previa;
    },
    null,
  ),
  'historico': (
    (e, d) => e.rodadas = _rodadas(d),
    (t) => t.tap(find.bySemanticsLabel('Histórico')),
  ),
  'ajustes': ((e, d) {}, (t) => t.tap(find.bySemanticsLabel('Ajustes'))),
  'ajustes-sem-conta': (
    (e, d) => e.conta = const ContaClaude(SituacaoClaude.semConta),
    (t) => t.tap(find.bySemanticsLabel('Ajustes')),
  ),
  'ajustes-sem-claude': (
    (e, d) => e.conta = const ContaClaude(SituacaoClaude.ausente),
    (t) => t.tap(find.bySemanticsLabel('Ajustes')),
  ),
  'atualizacao-guardado': (
    (e, d) {
      e.atualizacao = const Atualizacao('2.10.0', '');
      e.rodadas = _rodadas(d);
      e.ultima = _rodadas(d)[1];
    },
    null,
  ),
};

void main() {
  setUpAll(_carregarFontes);

  for (final MapEntry(key: nome, value: (preparo, acao)) in _cenarios.entries) {
    for (final tamanho in _tamanhos) {
      for (final claro in [false, true]) {
        final rotulo =
            '$nome ${tamanho.width.toInt()}x${tamanho.height.toInt()}'
            '${claro ? ' claro' : ''}';
        // Tema claro só no mínimo: o que muda é cor, não espaço.
        if (claro && tamanho != _tamanhos.first) continue;
        testWidgets(rotulo, (t) async {
          t.view.physicalSize = tamanho;
          t.view.devicePixelRatio = 1;
          t.platformDispatcher.platformBrightnessTestValue = claro
              ? Brightness.light
              : Brightness.dark;
          addTearDown(t.view.reset);
          addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);

          final base = Directory.systemTemp.createTempSync('neatly_layout');
          final downloads = Directory(p.join(base.path, 'Downloads'))
            ..createSync();
          final dados = Directory(p.join(base.path, 'dados'))..createSync();
          late Estado e;
          consultarContaClaude = () async =>
              e.conta ?? const ContaClaude(SituacaoClaude.conectado);
          await t.runAsync(() async {
            e = Estado(dados: dados.path, downloads: downloads.path);
            e.ajustes = e.ajustes.copyWith(modo: Modo.claude);
            preparo(e, downloads);
          });

          final chave = GlobalKey();
          await t.pumpWidget(
            RepaintBoundary(
              key: chave,
              child: ColoredBox(
                color: claro
                    ? const Color(0xFFF3F3F3)
                    : const Color(0xFF202020),
                child: NeatlyApp(estado: e),
              ),
            ),
          );
          await t.pump(const Duration(seconds: 1));
          if (acao != null) {
            await acao(t);
            await t.pump();
            await t.pump(const Duration(seconds: 1));
            await t.pump(const Duration(seconds: 1));
          }
          expect(t.takeException(), isNull);

          if (_fotos != null) {
            await t.runAsync(() async {
              final caixa =
                  chave.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final img = await caixa.toImage();
              final png = await img.toByteData(format: ui.ImageByteFormat.png);
              File(
                p.join(_fotos!, '${rotulo.replaceAll(' ', '_')}.png'),
              ).writeAsBytesSync(png!.buffer.asUint8List());
            });
          }

          e.dispose();
          await t.pumpWidget(const SizedBox());
          base.deleteSync(recursive: true);
        });
      }
    }
  }
}
