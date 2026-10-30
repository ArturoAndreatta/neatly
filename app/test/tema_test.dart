import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatly/estado.dart';
import 'package:neatly/tema.dart';
import 'package:neatly/ui/app.dart';
import 'package:neatly_core/neatly_core.dart';

double _contraste(Color a, Color b) {
  final (x, y) = (a.computeLuminance(), b.computeLuminance());
  return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
}

void main() {
  test('texto passa de 4,5:1 nos dois temas', () {
    for (final c in [Cores.claro, Cores.escuro]) {
      for (final fundo in [c.fundo, c.elevada]) {
        for (final texto in [c.tinta, c.suave, c.fraca, c.mentaTinta]) {
          expect(_contraste(texto, fundo), greaterThanOrEqualTo(4.5));
        }
        expect(_contraste(c.realce, fundo), greaterThanOrEqualTo(3));
      }
      // Aviso de baixo: pílula da cor da tinta.
      expect(_contraste(c.mentaSobreTinta, c.tinta), greaterThanOrEqualTo(4.5));
    }
  });

  test('cores deslizam na troca de tema', () {
    final meio = Cores.claro.lerp(Cores.escuro, .5);
    expect(meio.fundo, Color.lerp(Cores.claro.fundo, Cores.escuro.fundo, .5));
    expect(Cores.claro.lerp(Cores.escuro, 1).tinta, Cores.escuro.tinta);
  });

  testWidgets('Mica segue a escolha e, em Sistema, o Windows ao vivo', (
    tester,
  ) async {
    final raiz = Directory.systemTemp.createTempSync('tema');
    addTearDown(() => raiz.deleteSync(recursive: true));
    final e = Estado(dados: '${raiz.path}/dados', downloads: raiz.path);
    final janela = tester.platformDispatcher;
    janela.platformBrightnessTestValue = Brightness.light;
    addTearDown(janela.clearPlatformBrightnessTestValue);
    final mica = <bool>[];
    await tester.pumpWidget(
      NeatlyApp(estado: e, mica: (escuro) async => mica.add(escuro)),
    );

    e.trocarTema(Tema.escuro);
    await tester.pumpAndSettle();
    expect(mica, [true]);
    expect(
      Cores.de(tester.element(find.byType(Casca))).fundo,
      Cores.escuro.fundo,
    );

    // Escolha fixa: o Windows trocar não mexe.
    janela.platformBrightnessTestValue = Brightness.light;
    e.trocarTema(Tema.sistema);
    await tester.pumpAndSettle();
    expect(mica, [true, false]);
    janela.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(mica, [true, false, true]);
    expect(
      Cores.de(tester.element(find.byType(Casca))).fundo,
      Cores.escuro.fundo,
    );
    expect(Ajustes.carregar(e.dados).tema, Tema.sistema);
    e.dispose();
  });
}
