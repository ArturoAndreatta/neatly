import 'dart:convert';
import 'dart:io';

import 'planejador_claude.dart';

/// Em que pé o Claude Code está neste computador.
enum SituacaoClaude { ausente, semConta, conectado }

/// Claude Code instalado ou não, e com qual conta.
class ContaClaude {
  const ContaClaude(this.situacao, {this.email});

  final SituacaoClaude situacao;

  /// E-mail da conta vinculada, quando o Claude Code informa.
  final String? email;

  bool get pronta => situacao == SituacaoClaude.conectado;

  /// O que falta para usar o modo Claude; null quando já dá.
  String? get falta => switch (situacao) {
    SituacaoClaude.ausente => 'Precisa do Claude Code instalado',
    SituacaoClaude.semConta => 'Vincule sua conta do Claude em Ajustes',
    SituacaoClaude.conectado => null,
  };
}

/// Lê a saída de `claude auth status` (JSON).
ContaClaude lerStatusClaude(String saida) {
  try {
    final j = jsonDecode(saida);
    if (j is Map && j['loggedIn'] == true) {
      return ContaClaude(
        SituacaoClaude.conectado,
        email: j['email'] is String ? j['email'] as String : null,
      );
    }
  } on FormatException {
    // Versão antiga sem `auth status`: cai no "sem conta".
  }
  return const ContaClaude(SituacaoClaude.semConta);
}

/// Pergunta ao Claude Code se há conta vinculada.
Future<ContaClaude> verificarContaClaude() async {
  final exe = acharClaude();
  if (exe == null) return const ContaClaude(SituacaoClaude.ausente);
  try {
    final r = await Process.run(
      exe,
      ['auth', 'status', '--json'],
      runInShell: exe.endsWith('.cmd'),
      stdoutEncoding: utf8,
    ).timeout(const Duration(seconds: 20));
    return lerStatusClaude(r.stdout as String);
  } on Object {
    return const ContaClaude(SituacaoClaude.semConta);
  }
}

/// Abre uma janela do terminal com o login do Claude Code. Ele abre o
/// navegador para entrar com a conta; a janela fecha sozinha no fim.
Future<void> abrirLoginClaude() async {
  final exe = acharClaude();
  if (exe == null) return;
  await Process.start('cmd.exe', [
    '/c',
    'start',
    'Neatly - entrar no Claude',
    exe,
    'auth',
    'login',
  ]);
}

/// Abre uma janela do PowerShell com o instalador oficial do Claude Code,
/// seguido do login.
Future<void> abrirInstalacaoClaude() async {
  const script =
      r"irm https://claude.ai/install.ps1 | iex; "
      r"& (Join-Path $env:USERPROFILE '.local\bin\claude.exe') auth login";
  await Process.start('cmd.exe', [
    '/c',
    'start',
    'Neatly - instalar o Claude Code',
    'powershell.exe',
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    script,
  ]);
}
