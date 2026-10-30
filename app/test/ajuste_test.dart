import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatly/estado.dart';
import 'package:neatly/tema.dart';
import 'package:neatly/ui/ajustes_ui.dart';
import 'package:neatly/ui/previa.dart';
import 'package:neatly_core/neatly_core.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory raiz;
  late Directory dados;
  late Estado estado;

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('neatly-ui-raiz-');
    dados = Directory.systemTemp.createTempSync('neatly-ui-dados-');
    estado = Estado(dados: dados.path, downloads: raiz.path);
  });
  tearDown(() {
    estado.dispose();
    raiz.deleteSync(recursive: true);
    dados.deleteSync(recursive: true);
  });

  Plano plano(Modo modo) => Plano(
    raiz: raiz.path,
    modo: modo,
    movimentos: [
      for (final (nome, destino) in [
        ('boleto-energia-outubro-de-2026-segunda-via.pdf', 'Finanças/Boletos'),
        ('foto.png', 'Imagens'),
        ('EssentialsX.jar', 'Minecraft/Plugins'),
      ])
        Movimento(
          ArquivoSolto(
            caminho: p.join(raiz.path, nome),
            tamanho: 10,
            modificado: DateTime(2026),
          ),
          destino,
        ),
    ],
  );

  Future<void> montar(WidgetTester t, Widget filho) async {
    // Perto da janela mínima; a fonte de teste (Ahem) é mais larga que a
    // Segoe, então sobra um pouco de largura.
    t.view.physicalSize = const Size(480, 500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: tema(Brightness.dark),
        home: Scaffold(body: filho),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('campo Ajustar só no modo Claude, cabe na largura mínima', (
    t,
  ) async {
    estado.plano = plano(Modo.claude);
    estado.pedidoAplicado = 'junta Boletos dentro de Finanças';
    await montar(t, Previa(estado: estado));
    expect(find.textContaining('Ajustar'), findsOneWidget);
    expect(find.text('Guardar isso nas suas regras?'), findsOneWidget);

    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    expect(
      estado.ajustes.regras,
      contains('junta Boletos dentro de Finanças.'),
    );
    expect(find.textContaining('Guardado'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();

    estado.plano = plano(Modo.script);
    await montar(t, Previa(estado: estado));
    expect(find.textContaining('Ajustar'), findsNothing);
  });

  testWidgets('regras nos ajustes com o padrão e restaurar escondido', (
    t,
  ) async {
    await montar(t, ConteudoAjustes(estado: estado));
    if (!estado.claudeInstalado) return;
    final caixa = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == regrasPadrao,
    );
    await t.scrollUntilVisible(caixa, 200);
    expect(caixa, findsOneWidget);
    expect(find.text('Salvar'), findsNothing);
  });
}
