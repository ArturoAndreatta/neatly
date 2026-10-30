import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ajustes.dart';

/// Um arquivo movido: de onde saiu e onde foi parar (caminhos completos).
class Mudanca {
  const Mudanca(this.de, this.para);

  factory Mudanca.deJson(Map<String, Object?> j) =>
      Mudanca(j['de']! as String, j['para']! as String);

  final String de;
  final String para;

  Map<String, Object?> toJson() => {'de': de, 'para': para};
}

/// Uma arrumação feita.
class Rodada {
  Rodada({
    required this.id,
    required this.quando,
    required this.modo,
    required this.agendada,
    required this.raiz,
    required this.mudancas,
    required this.pastasCriadas,
    this.falhas = 0,
    this.aviso,
    this.desfeita = false,
  });

  factory Rodada.deJson(Map<String, Object?> j) => Rodada(
    id: j['id']! as String,
    quando: DateTime.parse(j['quando']! as String),
    modo: Modo.de(j['modo']),
    agendada: j['agendada'] as bool? ?? false,
    raiz: j['raiz'] as String? ?? '',
    mudancas: [
      for (final m in (j['mudancas'] as List? ?? const []))
        Mudanca.deJson((m as Map).cast()),
    ],
    pastasCriadas: (j['pastasCriadas'] as List?)?.cast<String>() ?? const [],
    falhas: (j['falhas'] as num?)?.toInt() ?? 0,
    aviso: j['aviso'] as String?,
    desfeita: j['desfeita'] as bool? ?? false,
  );

  final String id;
  final DateTime quando;
  final Modo modo;
  final bool agendada;
  final String raiz;
  final List<Mudanca> mudancas;

  /// Pastas que esta rodada criou (o desfazer apaga as que ficarem vazias).
  final List<String> pastasCriadas;

  /// Arquivos que não saíram do lugar (em uso, sem permissão).
  final int falhas;
  final String? aviso;
  bool desfeita;

  /// Pastas de primeiro nível com quantos arquivos cada uma recebeu.
  Map<String, int> get porPasta {
    final m = <String, int>{};
    for (final x in mudancas) {
      final rel = p.relative(x.para, from: raiz);
      final topo = p.split(rel).first;
      m[topo] = (m[topo] ?? 0) + 1;
    }
    return Map.fromEntries(
      m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'quando': quando.toIso8601String(),
    'modo': modo.name,
    'agendada': agendada,
    'raiz': raiz,
    'mudancas': [for (final m in mudancas) m.toJson()],
    'pastasCriadas': pastasCriadas,
    'falhas': falhas,
    'aviso': aviso,
    'desfeita': desfeita,
  };
}

/// Rodadas gravadas em `historico.json`, da mais nova para a mais velha.
class Historico {
  Historico(this.dados);

  final String dados;
  static const maximo = 200;

  File get _arquivo => File(p.join(dados, 'historico.json'));

  List<Rodada> carregar() {
    final f = _arquivo;
    if (!f.existsSync()) return [];
    try {
      final lista = jsonDecode(f.readAsStringSync()) as List;
      return [for (final r in lista) Rodada.deJson((r as Map).cast())];
    } on Object {
      return [];
    }
  }

  void _gravar(List<Rodada> rodadas) {
    final f = _arquivo;
    f.parent.createSync(recursive: true);
    final tmp = File('${f.path}.tmp')
      ..writeAsStringSync(
        jsonEncode([for (final r in rodadas.take(maximo)) r.toJson()]),
      );
    tmp.renameSync(f.path);
  }

  void adicionar(Rodada r) => _gravar([r, ...carregar()]);

  void atualizar(Rodada r) =>
      _gravar([for (final x in carregar()) x.id == r.id ? r : x]);
}
