import 'dart:io';

import 'package:path/path.dart' as p;

import 'ajustes.dart';

/// Pasta de dados do Neatly (ajustes e histórico). `NEATLY_DADOS` troca
/// (desenvolvimento, sem mexer na instalação de verdade).
String pastaDados() {
  if (Platform.environment['NEATLY_DADOS'] case final x? when x.isNotEmpty) {
    return x;
  }
  final base =
      Platform.environment['LOCALAPPDATA'] ??
      p.join(Platform.environment['USERPROFILE'] ?? '.', 'AppData', 'Local');
  return p.join(base, 'Neatly');
}

String _expandir(String s) => s.replaceAllMapped(
  RegExp('%([^%]+)%'),
  (m) => Platform.environment[m[1]!] ?? m[0]!,
);

/// Downloads de verdade do usuário (mesmo se foi movida, ex.: para o
/// OneDrive). `NEATLY_PASTA` troca a pasta (usado nos testes).
String pastaDownloads() {
  final env = Platform.environment;
  if (env['NEATLY_PASTA'] case final x? when x.isNotEmpty) return x;
  try {
    final r = Process.runSync('reg', [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders',
      '/v',
      '{374DE290-123F-4565-9164-39C4925E467B}',
    ]);
    final m = RegExp(r'REG_(?:EXPAND_)?SZ\s+(.+)').firstMatch('${r.stdout}');
    if (m != null) {
      final caminho = _expandir(m[1]!.trim());
      if (Directory(caminho).existsSync()) return caminho;
    }
  } on ProcessException {
    // Sem reg.exe: cai no padrão.
  }
  return p.join(env['USERPROFILE'] ?? '.', 'Downloads');
}

const nomeTarefa = 'Neatly';

/// Quem está no Windows (`DOMINIO\usuario`): o gatilho de logon só deste
/// usuário não pede administrador.
String? usuarioAtual() {
  final env = Platform.environment;
  final nome = env['USERNAME'];
  if (nome == null || nome.isEmpty) return null;
  final dominio = env['USERDOMAIN'];
  return dominio == null || dominio.isEmpty ? nome : '$dominio\\$nome';
}

/// Espera depois do logon: rede e `claude` prontos antes de arrumar.
const atrasoAoLigar = 'PT2M';

/// XML da tarefa: diária (StartWhenAvailable: PC desligado no horário roda
/// assim que ligar) e/ou ao entrar no Windows, conforme [a].
String xmlTarefa(Agendamento a, String exe, {String? usuario}) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  final inicio = '2026-01-01T${a.horario}:00';
  final quando = [
    if (a.ativo) 'todo dia',
    if (a.aoLigar) 'ao ligar o PC',
  ].join(' e ');
  final diaria = !a.ativo
      ? ''
      : '''
    <CalendarTrigger>
      <StartBoundary>$inicio</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>
    </CalendarTrigger>
''';
  final logon = !a.aoLigar
      ? ''
      : '''
    <LogonTrigger>
      <Enabled>true</Enabled>
${usuario == null ? '' : '      <UserId>${esc(usuario)}</UserId>\n'}      <Delay>$atrasoAoLigar</Delay>
    </LogonTrigger>
''';
  return '''
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Neatly: arruma a pasta Downloads $quando.</Description></RegistrationInfo>
  <Triggers>
$diaria$logon  </Triggers>
  <Principals><Principal id="Author"><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <ExecutionTimeLimit>PT15M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec><Command>${esc(exe)}</Command><Arguments>--agendado</Arguments></Exec>
  </Actions>
</Task>
''';
}

/// Cria, troca ou remove a tarefa no Agendador do Windows.
/// Devolve false se o Windows recusar.
bool aplicarAgendamento(Agendamento a, {String? exe}) {
  if (!a.algum) {
    Process.runSync('schtasks', ['/Delete', '/TN', nomeTarefa, '/F']);
    return true;
  }
  final xml = File(p.join(Directory.systemTemp.path, 'neatly-tarefa.xml'));
  // schtasks só lê o XML em UTF-16 com BOM.
  final unidades = xmlTarefa(
    a,
    exe ?? Platform.resolvedExecutable,
    usuario: usuarioAtual(),
  ).codeUnits;
  final bytes = <int>[0xFF, 0xFE];
  for (final u in unidades) {
    bytes
      ..add(u & 0xFF)
      ..add(u >> 8);
  }
  xml.writeAsBytesSync(bytes);
  try {
    final r = Process.runSync('schtasks', [
      '/Create',
      '/TN',
      nomeTarefa,
      '/XML',
      xml.path,
      '/F',
    ]);
    return r.exitCode == 0;
  } finally {
    try {
      xml.deleteSync();
    } on FileSystemException {
      // Temporário, o Windows limpa.
    }
  }
}
