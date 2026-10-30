import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ajustes.dart';
import 'windows.dart';

/// Arquivos do Neatly 1 (PowerShell) na pasta de dados.
const _arquivosV1 = [
  'abrir-painel.vbs',
  'comum.ps1',
  'config.padrao.json',
  'configurar-token.cmd', //
  'configurar-token.ps1', 'desinstalar.cmd', 'desinstalar.ps1', 'instalar.ps1',
  'neatly.ico', 'oculto.vbs', 'organizar.ps1', 'painel.html', 'painel.ps1',
  'config.json', 'token.dat', 'versao.json', 'claude-path.txt',
];

/// Traz modo e horário do Neatly 1 e limpa os arquivos dele.
/// Devolve os ajustes novos, ou null se não havia instalação antiga.
Ajustes? migrarV1(String dados, {bool mexerNoWindows = true}) {
  final antigo = File(p.join(dados, 'config.json'));
  if (!antigo.existsSync() || Ajustes.arquivo(dados).existsSync()) return null;

  var modo = Modo.script;
  try {
    final j = jsonDecode(antigo.readAsStringSync().replaceFirst('﻿', ''));
    if (j is Map && j['modo'] == 'claude') modo = Modo.claude;
  } on Object {
    // Config quebrada: segue com o padrão.
  }

  var agenda = Agendamento(modo: modo);
  if (mexerNoWindows) {
    final r = Process.runSync('schtasks', [
      '/Query',
      '/TN',
      nomeTarefa,
      '/XML',
    ]);
    final xml = '${r.stdout}';
    final h = RegExp(r'<StartBoundary>[^T]*T(\d{2}):(\d{2})').firstMatch(xml);
    if (h != null) {
      agenda = agenda.copyWith(
        hora: int.parse(h[1]!),
        minuto: int.parse(h[2]!),
        ativo: !xml.contains('<Enabled>false</Enabled>'),
      );
    }
    for (final t in [
      'Neatly - Painel',
      'Organizar Downloads',
      'Organizar Downloads - Painel',
      'Organizar Downloads (Claude)',
      'Painel Downloads (servidor)',
    ]) {
      Process.runSync('schtasks', ['/Delete', '/TN', t, '/F']);
    }
  }

  final ajustes = Ajustes(modo: modo, agendamento: agenda);
  ajustes.salvar(dados);

  final hist = File(p.join(dados, 'historico.jsonl'));
  if (hist.existsSync()) hist.renameSync(p.join(dados, 'historico-v1.jsonl'));
  for (final nome in _arquivosV1) {
    final f = File(p.join(dados, nome));
    try {
      if (f.existsSync()) f.deleteSync();
    } on FileSystemException {
      continue;
    }
  }
  return ajustes;
}
