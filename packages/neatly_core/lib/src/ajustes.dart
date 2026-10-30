import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Como os arquivos são organizados.
enum Modo {
  /// Claude Haiku lê nome e trecho e cria pastas por assunto.
  claude,

  /// Regras fixas por tipo e nome, sem IA.
  script;

  static Modo de(Object? v) =>
      Modo.values.firstWhere((m) => m.name == v, orElse: () => Modo.script);
}

/// Arrumação automática diária.
class Agendamento {
  const Agendamento({
    this.ativo = true,
    this.hora = 9,
    this.minuto = 0,
    this.modo = Modo.script,
  });

  factory Agendamento.deJson(Map<String, Object?> j) => Agendamento(
    ativo: j['ativo'] as bool? ?? true,
    hora: (j['hora'] as num?)?.toInt() ?? 9,
    minuto: (j['minuto'] as num?)?.toInt() ?? 0,
    modo: Modo.de(j['modo']),
  );

  final bool ativo;
  final int hora;
  final int minuto;
  final Modo modo;

  Agendamento copyWith({bool? ativo, int? hora, int? minuto, Modo? modo}) =>
      Agendamento(
        ativo: ativo ?? this.ativo,
        hora: hora ?? this.hora,
        minuto: minuto ?? this.minuto,
        modo: modo ?? this.modo,
      );

  /// "09:00".
  String get horario =>
      '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';

  Map<String, Object?> toJson() => {
    'ativo': ativo,
    'hora': hora,
    'minuto': minuto,
    'modo': modo.name,
  };
}

/// Padrões que nunca saem do lugar nem são enviados ao Claude.
const ignorarPadrao = [
  'desktop.ini',
  'thumbs.db',
  '*.crdownload',
  '*.part',
  '*.partial',
  '*.download',
  '*.tmp',
  '~\$*',
  '*.env',
  '.env*',
  '*.pem',
  '*.key',
  '*.pfx',
  '*.p12',
  '*.kdbx',
  'id_rsa*',
  'id_ed25519*',
  '*credentials*',
  '*service-account*',
  '*firebase-adminsdk*',
];

/// Ajustes do usuário, gravados em `ajustes.json` na pasta de dados.
class Ajustes {
  const Ajustes({
    this.pasta,
    this.modo = Modo.claude,
    this.agendamento = const Agendamento(),
    this.minutosRecentes = 10,
    this.ignorar = ignorarPadrao,
  });

  factory Ajustes.deJson(Map<String, Object?> j) => Ajustes(
    pasta: j['pasta'] as String?,
    modo: Modo.de(j['modo']),
    agendamento: j['agendamento'] is Map
        ? Agendamento.deJson((j['agendamento'] as Map).cast())
        : const Agendamento(),
    minutosRecentes: (j['minutosRecentes'] as num?)?.toInt() ?? 10,
    ignorar: (j['ignorar'] as List?)?.cast<String>() ?? ignorarPadrao,
  );

  /// Pasta organizada; null usa a Downloads do Windows.
  final String? pasta;

  /// Modo do botão Organizar.
  final Modo modo;
  final Agendamento agendamento;

  /// Arquivo mexido há menos que isso ainda pode estar baixando.
  final int minutosRecentes;
  final List<String> ignorar;

  Ajustes copyWith({
    String? pasta,
    Modo? modo,
    Agendamento? agendamento,
    int? minutosRecentes,
  }) => Ajustes(
    pasta: pasta ?? this.pasta,
    modo: modo ?? this.modo,
    agendamento: agendamento ?? this.agendamento,
    minutosRecentes: minutosRecentes ?? this.minutosRecentes,
    ignorar: ignorar,
  );

  Map<String, Object?> toJson() => {
    'versao': 2,
    'pasta': pasta,
    'modo': modo.name,
    'agendamento': agendamento.toJson(),
    'minutosRecentes': minutosRecentes,
    'ignorar': ignorar,
  };

  static File arquivo(String dados) => File(p.join(dados, 'ajustes.json'));

  static Ajustes carregar(String dados) {
    final f = arquivo(dados);
    if (!f.existsSync()) return const Ajustes();
    try {
      return Ajustes.deJson(
        jsonDecode(f.readAsStringSync()) as Map<String, Object?>,
      );
    } on Object {
      return const Ajustes();
    }
  }

  void salvar(String dados) {
    final f = arquivo(dados);
    f.parent.createSync(recursive: true);
    // Grava num temporário e troca: um desligamento no meio não corrompe.
    final tmp = File('${f.path}.tmp')
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(toJson()));
    tmp.renameSync(f.path);
  }
}
