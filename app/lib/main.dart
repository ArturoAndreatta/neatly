import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:neatly_core/neatly_core.dart';
import 'package:window_manager/window_manager.dart';

import 'agendado.dart';
import 'estado.dart';
import 'ui/app.dart';

Future<void> main(List<String> args) async {
  // Rodada do Agendador do Windows: arruma e sai, sem janela.
  if (args.contains('--agendado')) exit(await rodarAgendado());

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await acrylic.Window.initialize();

  final estado = Estado(dados: pastaDados());

  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(460, 640),
      minimumSize: Size(420, 560),
      center: true,
      title: 'Neatly',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
    ),
    () async {
      await aplicarMica(temaEscuro(estado.ajustes.tema));
      await windowManager.show();
      await windowManager.focus();
    },
  );

  runApp(NeatlyApp(estado: estado));
  estado.procurarAtualizacao();
}
