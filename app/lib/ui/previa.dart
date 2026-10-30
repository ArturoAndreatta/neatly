import 'dart:io';

import 'package:flutter/material.dart';
import 'package:neatly_core/neatly_core.dart';
import 'package:path/path.dart' as p;

import '../estado.dart';
import '../tema.dart';
import 'barra.dart';
import 'comum.dart';

/// Árvore do que vai acontecer, antes de mover qualquer coisa.
class Previa extends StatelessWidget {
  const Previa({super.key, required this.estado});

  final Estado estado;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final plano = estado.plano;
    if (plano == null) return const SizedBox.shrink();
    final arvore = plano.arvore(
      (rel) =>
          Directory(p.joinAll([plano.raiz, ...rel.split('/')])).existsSync(),
    );
    final n = plano.movimentos.length;
    // Com pasta inteira no meio, "arquivos" deixa de ser verdade.
    final itens = plano.movimentos.any((m) => m.arquivo.pasta)
        ? (n == 1 ? 'item' : 'itens')
        : (n == 1 ? 'arquivo' : 'arquivos');
    final pastas = arvore.length;
    final novas = arvore.where((n) => n.nova).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Prévia',
            style: TextStyle(
              fontFamily: fonteDisplay,
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: -.5,
              color: c.tinta,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(iconeModo(plano.modo), size: 14, color: c.suave),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '$n $itens em $pastas '
                  '${pastas == 1 ? 'pasta' : 'pastas'}'
                  '${novas == 0
                      ? ''
                      : novas == pastas
                      ? ' ${pastas == 1 ? 'nova' : 'novas'}'
                      : ', $novas ${novas == 1 ? 'nova' : 'novas'}'}',
                  style: TextStyle(fontSize: 13.5, color: c.suave),
                ),
              ),
            ],
          ),
          if (plano.aviso != null) ...[
            const SizedBox(height: 12),
            Entrada(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: c.avisoFundo,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: c.aviso),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        plano.aviso!,
                        style: TextStyle(
                          fontSize: 13,
                          color: c.aviso,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: c.superficie,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.linha),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (var i = 0; i < arvore.length; i++)
                      Entrada(
                        atraso: i,
                        child: _Pasta(no: arvore[i], nivel: 0, aberta: n <= 24),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              BotaoTexto(texto: 'Voltar', onTap: estado.cancelar),
              const SizedBox(width: 8),
              BotaoPrincipal(texto: 'Mover $n $itens', onTap: estado.mover),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pasta extends StatefulWidget {
  const _Pasta({required this.no, required this.nivel, this.aberta = false});

  final NoPasta no;
  final int nivel;
  final bool aberta;

  @override
  State<_Pasta> createState() => _PastaState();
}

class _PastaState extends State<_Pasta> {
  late bool _aberta = widget.aberta;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final no = widget.no;
    final recuo = 14.0 + widget.nivel * 20;
    final filhas = no.filhas.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    // Pastas que viram esta vêm primeiro, como "conteúdo de X".
    final arquivos = [
      for (final a in no.juntadas) (a, 'conteúdo de ${a.nome}'),
      for (final a in [
        ...no.arquivos,
      ]..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase())))
        (a, a.nome),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Pressionavel(
            onTap: () => setState(() => _aberta = !_aberta),
            rotulo: '${no.nome}, ${no.total} arquivos',
            raio: 8,
            escala: .99,
            child: Padding(
              padding: EdgeInsets.fromLTRB(recuo - 6, 7, 10, 7),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _aberta ? .25 : 0,
                    duration: Mov.rapido,
                    curve: Mov.saida,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: c.fraca,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _aberta ? Icons.folder_open_rounded : Icons.folder_rounded,
                    size: 18,
                    color: no.nova ? c.realce : c.suave,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            no.nome,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.tinta,
                            ),
                          ),
                        ),
                        if (no.nova) ...[
                          const SizedBox(width: 8),
                          const Selo('nova'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${no.total}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: c.fraca,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: Mov.base,
          curve: Mov.saida,
          alignment: Alignment.topCenter,
          child: !_aberta
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final f in filhas)
                      Entrada(
                        child: _Pasta(
                          no: f,
                          nivel: widget.nivel + 1,
                          aberta: widget.aberta,
                        ),
                      ),
                    for (var i = 0; i < arquivos.length; i++)
                      Entrada(
                        atraso: i,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(recuo + 26, 4, 16, 4),
                          child: Row(
                            children: [
                              Icon(
                                arquivos[i].$1.pasta
                                    ? Icons.folder_outlined
                                    : Icons.insert_drive_file_outlined,
                                size: 15,
                                color: c.fraca,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  arquivos[i].$2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: c.suave,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                  ],
                ),
        ),
      ],
    );
  }
}
