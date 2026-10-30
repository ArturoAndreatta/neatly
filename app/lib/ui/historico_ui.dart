import 'package:flutter/material.dart';
import 'package:neatly_core/neatly_core.dart';
import 'package:path/path.dart' as p;

import '../estado.dart';
import '../tema.dart';
import 'barra.dart';
import 'comum.dart';
import 'inicio.dart';

/// Conteúdo da gaveta de histórico: procurar arquivo e as rodadas.
class ConteudoHistorico extends StatefulWidget {
  const ConteudoHistorico({super.key, required this.estado});

  final Estado estado;

  @override
  State<ConteudoHistorico> createState() => _ConteudoHistoricoState();
}

class _ConteudoHistoricoState extends State<ConteudoHistorico> {
  final _busca = TextEditingController();
  String _termo = '';

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final rodadas = widget.estado.rodadas;
    final termo = _termo.trim().toLowerCase();
    final achados = termo.isEmpty
        ? const <Mudanca>[]
        : [
            for (final r in rodadas)
              if (!r.desfeita)
                for (final m in r.mudancas)
                  if (p.basename(m.para).toLowerCase().contains(termo)) m,
          ].take(80).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: TextField(
            controller: _busca,
            onChanged: (v) => setState(() => _termo = v),
            style: TextStyle(fontSize: 14, color: c.tinta),
            cursorColor: c.mentaTinta,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Procurar um arquivo guardado',
              hintStyle: TextStyle(color: c.fraca, fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: c.fraca),
              prefixIconConstraints: const BoxConstraints(minWidth: 38),
              filled: true,
              fillColor: c.tinta.withValues(alpha: .04),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.linha),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.linha),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.menta, width: 1.5),
              ),
            ),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: Mov.rapido,
            child: termo.isNotEmpty
                ? _Achados(
                    key: const ValueKey('achados'),
                    achados: achados,
                    estado: widget.estado,
                  )
                : rodadas.isEmpty
                ? Center(
                    key: const ValueKey('vazio'),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Cada arrumação aparece aqui, com o que foi para onde.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.fraca,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    key: const ValueKey('lista'),
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                    itemCount: rodadas.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: 12,
                      endIndent: 12,
                      color: c.linha,
                    ),
                    itemBuilder: (_, i) => Entrada(
                      atraso: i,
                      child: _Rodada(rodada: rodadas[i], estado: widget.estado),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _Achados extends StatelessWidget {
  const _Achados({super.key, required this.achados, required this.estado});

  final List<Mudanca> achados;
  final Estado estado;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    if (achados.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          'Nenhum arquivo guardado com esse nome.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.fraca, fontSize: 13.5),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
      children: [
        for (final m in achados)
          Pressionavel(
            onTap: () => estado.abrirPasta(m.para),
            rotulo: 'Mostrar ${p.basename(m.para)} no Explorer',
            raio: 9,
            escala: .99,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.basename(m.para),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: c.tinta,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    p
                        .relative(p.dirname(m.para), from: estado.pasta)
                        .replaceAll(r'\', ' › '),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.suave),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Rodada extends StatefulWidget {
  const _Rodada({required this.rodada, required this.estado});

  final Rodada rodada;
  final Estado estado;

  @override
  State<_Rodada> createState() => _RodadaState();
}

class _RodadaState extends State<_Rodada> {
  bool _aberta = false;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final r = widget.rodada;
    final n = r.mudancas.length;
    final porPasta = r.porPasta.entries.toList();
    final resumo = [
      for (final e in porPasta.take(3)) '${e.key} ${e.value}',
      if (porPasta.length > 3) '+${porPasta.length - 3}',
    ].join(' · ');
    final apagada = r.desfeita;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressionavel(
            onTap: n == 0 ? null : () => setState(() => _aberta = !_aberta),
            rotulo: 'Arrumação de ${quando(r.quando)}',
            raio: 10,
            escala: .99,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(iconeModo(r.modo), size: 16, color: c.fraca),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${_maiuscula(quando(r.quando))} · $n ${n == 1 ? 'arquivo' : 'arquivos'}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: apagada ? c.fraca : c.tinta,
                                  decoration: apagada
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: c.fraca,
                                ),
                              ),
                            ),
                            if (r.agendada) ...[
                              const SizedBox(width: 6),
                              Selo(
                                'automática',
                                fundo: c.tinta.withValues(alpha: .06),
                                cor: c.suave,
                              ),
                            ],
                          ],
                        ),
                        if (resumo.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            resumo,
                            style: TextStyle(fontSize: 12.5, color: c.suave),
                          ),
                        ],
                        if (r.falhas > 0)
                          Text(
                            '${r.falhas} em uso ficaram no lugar',
                            style: TextStyle(fontSize: 12.5, color: c.aviso),
                          ),
                        if (r.aviso != null && n == 0)
                          Text(
                            r.aviso!,
                            style: TextStyle(fontSize: 12.5, color: c.aviso),
                          ),
                      ],
                    ),
                  ),
                  if (n > 0)
                    apagada
                        ? Padding(
                            padding: const EdgeInsets.only(top: 2, right: 6),
                            child: Text(
                              'Desfeita',
                              style: TextStyle(fontSize: 12.5, color: c.fraca),
                            ),
                          )
                        : BotaoTexto(
                            texto: 'Desfazer',
                            onTap: () => widget.estado.desfazerRodada(r),
                          ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: Mov.base,
            curve: Mov.saida,
            alignment: Alignment.topCenter,
            child: !_aberta
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(38, 0, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final m in r.mudancas.take(60))
                          Pressionavel(
                            onTap: apagada
                                ? null
                                : () => widget.estado.abrirPasta(m.para),
                            rotulo: p.basename(m.para),
                            raio: 6,
                            escala: .99,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: p.basename(m.de),
                                      style: TextStyle(color: c.tinta),
                                    ),
                                    TextSpan(
                                      text:
                                          '  ${p.relative(p.dirname(m.para), from: r.raiz).replaceAll(r'\', ' › ')}',
                                      style: TextStyle(color: c.fraca),
                                    ),
                                  ],
                                ),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ),
                        if (r.mudancas.length > 60)
                          Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(
                              'e mais ${r.mudancas.length - 60}',
                              style: TextStyle(fontSize: 12.5, color: c.fraca),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

String _maiuscula(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
