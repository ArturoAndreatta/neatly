import 'dart:async';
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
                // Plano ajustado: a árvore nova entra em cascata por cima da
                // antiga, que esmaece enquanto o Claude replaneja.
                child: AnimatedOpacity(
                  duration: Mov.base,
                  curve: Curves.ease,
                  opacity: estado.ajustando ? .45 : 1,
                  child: AnimatedSwitcher(
                    duration: Mov.base,
                    switchInCurve: Mov.saida,
                    switchOutCurve: Curves.easeOut,
                    transitionBuilder: (w, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(
                        scale: Tween(begin: .985, end: 1.0).animate(a),
                        alignment: Alignment.topCenter,
                        child: w,
                      ),
                    ),
                    child: ListView(
                      key: ObjectKey(plano),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        for (var i = 0; i < arvore.length; i++)
                          Entrada(
                            atraso: i,
                            child: _Pasta(
                              no: arvore[i],
                              nivel: 0,
                              aberta: n <= 24,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (plano.modo == Modo.claude) ...[
            const SizedBox(height: 12),
            _CampoAjuste(estado: estado),
          ],
          const SizedBox(height: 16),
          AnimatedOpacity(
            duration: Mov.rapido,
            opacity: estado.ajustando ? .5 : 1,
            child: IgnorePointer(
              ignoring: estado.ajustando,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  BotaoTexto(texto: 'Voltar', onTap: estado.cancelar),
                  const SizedBox(width: 8),
                  BotaoPrincipal(texto: 'Mover $n $itens', onTap: estado.mover),
                ],
              ),
            ),
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

/// "Ajustar...": pedido em texto livre que o Claude aplica no plano. Depois
/// de um ajuste, oferece guardar o pedido nas regras de gosto.
class _CampoAjuste extends StatefulWidget {
  const _CampoAjuste({required this.estado});

  final Estado estado;

  @override
  State<_CampoAjuste> createState() => _CampoAjusteState();
}

class _CampoAjusteState extends State<_CampoAjuste> {
  final _texto = TextEditingController();
  final _foco = FocusNode();
  bool _guardado = false;
  Timer? _apagar;

  @override
  void initState() {
    super.initState();
    _texto.addListener(() => setState(() {}));
    _foco.addListener(() => setState(() {}));
  }

  Future<void> _enviar() async {
    final pedido = _texto.text.trim();
    if (pedido.isEmpty || widget.estado.ajustando) return;
    setState(() => _guardado = false);
    await widget.estado.ajustar(pedido);
    if (!mounted) return;
    if (widget.estado.erroAjuste == null) _texto.clear();
  }

  void _guardar() {
    widget.estado.guardarPedido();
    setState(() => _guardado = true);
    _apagar?.cancel();
    _apagar = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _guardado = false);
    });
  }

  @override
  void dispose() {
    _apagar?.cancel();
    _texto.dispose();
    _foco.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final e = widget.estado;
    final ajustando = e.ajustando;
    final pode = _texto.text.trim().isNotEmpty && !ajustando;

    // Uma faixa por vez acima do campo: erro, oferta de guardar ou "guardado".
    final Widget faixa;
    if (e.erroAjuste != null) {
      faixa = _Faixa(
        key: const ValueKey('erro'),
        icone: Icons.info_outline_rounded,
        cor: c.aviso,
        fundo: c.avisoFundo,
        texto: '${e.erroAjuste} O plano continua o mesmo.',
      );
    } else if (e.pedidoAplicado != null) {
      faixa = _Faixa(
        key: ValueKey('guardar ${e.pedidoAplicado}'),
        icone: Icons.bookmark_add_outlined,
        cor: c.tinta,
        fundo: c.mentaFundo,
        texto: 'Guardar isso nas suas regras?',
        fim: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BotaoTexto(texto: 'Guardar', cor: c.mentaTinta, onTap: _guardar),
            BotaoIcone(
              icone: Icons.close_rounded,
              dica: 'Agora não',
              tamanho: 16,
              onTap: e.esquecerPedido,
            ),
          ],
        ),
      );
    } else if (_guardado) {
      faixa = _Faixa(
        key: const ValueKey('guardado'),
        icone: Icons.check_rounded,
        cor: c.mentaTinta,
        fundo: c.mentaFundo,
        texto: 'Guardado. Vale para as próximas arrumações.',
      );
    } else {
      faixa = const SizedBox(key: ValueKey('nada'), width: double.infinity);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: Mov.base,
          curve: Mov.saida,
          alignment: Alignment.bottomCenter,
          child: AnimatedSwitcher(
            duration: Mov.base,
            switchInCurve: Mov.saida,
            switchOutCurve: Curves.easeOut,
            transitionBuilder: (w, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, .25),
                  end: Offset.zero,
                ).animate(a),
                child: w,
              ),
            ),
            layoutBuilder: (atual, antigos) => Stack(
              alignment: Alignment.bottomCenter,
              children: [...antigos, ?atual],
            ),
            child: faixa,
          ),
        ),
        AnimatedContainer(
          duration: Mov.rapido,
          curve: Curves.ease,
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            color: c.superficie,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _foco.hasFocus ? c.menta : c.linha,
              width: _foco.hasFocus ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: _foco.hasFocus ? c.mentaTinta : c.fraca,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _texto,
                  focusNode: _foco,
                  readOnly: ajustando,
                  maxLength: 300,
                  buildCounter:
                      (
                        _, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _enviar(),
                  cursorColor: c.menta,
                  style: TextStyle(fontSize: 13.5, color: c.tinta),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    hintText: ajustando
                        ? 'Replanejando...'
                        : 'Ajustar, ex.: junta Boletos em Finanças',
                    hintMaxLines: 1,
                    hintStyle: TextStyle(
                      fontSize: 13.5,
                      color: c.fraca,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Pressionavel(
                onTap: pode ? _enviar : null,
                rotulo: 'Aplicar ajuste',
                raio: 999,
                realce: false,
                escala: .92,
                child: AnimatedContainer(
                  duration: Mov.rapido,
                  curve: Curves.ease,
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: pode ? c.menta : c.tinta.withValues(alpha: .06),
                  ),
                  child: AnimatedSwitcher(
                    duration: Mov.rapido,
                    transitionBuilder: (w, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(
                        scale: Tween(begin: .8, end: 1.0).animate(a),
                        child: w,
                      ),
                    ),
                    child: ajustando
                        ? Padding(
                            key: const ValueKey('girando'),
                            padding: const EdgeInsets.all(9),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.menta,
                            ),
                          )
                        : Icon(
                            Icons.arrow_upward_rounded,
                            key: const ValueKey('enviar'),
                            size: 17,
                            color: pode ? c.sobreMenta : c.fraca,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Faixa extends StatelessWidget {
  const _Faixa({
    super.key,
    required this.icone,
    required this.cor,
    required this.fundo,
    required this.texto,
    this.fim,
  });

  final IconData icone;
  final Color cor;
  final Color fundo;
  final String texto;
  final Widget? fim;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: EdgeInsets.fromLTRB(12, 4, fim == null ? 12 : 2, 4),
        decoration: BoxDecoration(
          color: fundo,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icone, size: 16, color: cor),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  texto,
                  style: TextStyle(fontSize: 13, color: cor, height: 1.35),
                ),
              ),
            ),
            ?fim,
          ],
        ),
      ),
    );
  }
}
