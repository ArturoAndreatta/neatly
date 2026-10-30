import 'dart:io';

import 'package:neatly_core/neatly_core.dart';

/// Arrumação disparada pelo Agendador do Windows (todo dia ou ao ligar o
/// PC). Aplica direto, sem prévia: o histórico guarda tudo para desfazer
/// depois. Sem nada solto, ou se acabou de arrumar, sai em silêncio.
/// Devolve o código de saída (0 ok, 1 algum arquivo ficou).
Future<int> rodarAgendado() async {
  final dados = pastaDados();
  final ajustes = migrarV1(dados) ?? Ajustes.carregar(dados);
  final pasta = ajustes.pasta ?? pastaDownloads();
  if (!Directory(pasta).existsSync()) return 1;
  final historico = Historico(dados);
  final rodadas = historico.carregar();
  final modo = ajustes.agendamento.modo;
  if (arrumouHaPouco(rodadas)) return 0;
  if (!temOQueOrganizar(pasta, ajustes, modo, rodadas: rodadas)) return 0;
  final plano = await montarPlano(pasta, ajustes, modo, rodadas: rodadas);
  if (plano.vazio && plano.aviso == null) return 0;
  final r = aplicar(plano, historico, agendada: true);
  return r.falhas > 0 ? 1 : 0;
}
