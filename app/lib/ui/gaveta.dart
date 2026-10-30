import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema.dart';
import 'comum.dart';

/// Painel que desliza da direita sobre um véu. Esc ou clique fora fecha.
///
/// O conteúdo fica montado (fora da tela) depois da primeira abertura: abrir
/// de novo não reconstrói a lista no primeiro quadro do deslize. Painel e véu
/// andam só por camada (deslize e opacidade), sem repintar o conteúdo.
class Gaveta extends StatefulWidget {
  const Gaveta({
    super.key,
    required this.aberta,
    required this.titulo,
    required this.aoFechar,
    required this.child,
  });

  final bool aberta;
  final String titulo;
  final VoidCallback aoFechar;
  final Widget child;

  @override
  State<Gaveta> createState() => _GavetaState();
}

class _GavetaState extends State<Gaveta> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
    vsync: this,
    duration: Mov.gavetaDur,
    // Fechar é mais rápido que abrir: o sistema responde, não decide.
    reverseDuration: const Duration(milliseconds: 220),
    value: widget.aberta ? 1 : 0,
  )..addStatusListener((_) => setState(() {}));
  late final _curva = CurvedAnimation(
    parent: _ctrl,
    curve: Mov.gaveta,
    reverseCurve: Mov.gaveta.flipped,
  );
  late final _deslize = Tween(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).animate(_curva);
  final _foco = FocusNode(debugLabel: 'Gaveta');
  bool _montada = false;

  @override
  void initState() {
    super.initState();
    _montada = widget.aberta;
  }

  @override
  void didUpdateWidget(Gaveta antes) {
    super.didUpdateWidget(antes);
    if (widget.aberta == antes.aberta) return;
    if (widget.aberta) {
      _montada = true;
      _ctrl.forward();
      // Já montada, o autofocus não age de novo: o Esc precisa do foco.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.aberta) _foco.requestFocus();
      });
    } else {
      _foco.unfocus();
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _curva.dispose();
    _ctrl.dispose();
    _foco.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final reduzir = Mov.reduzir(context);
    final fechada = _ctrl.status == AnimationStatus.dismissed;
    if (!_montada) return const SizedBox.shrink();
    // Sobra sempre uma faixa do véu à esquerda para clicar e fechar.
    final largura = math.min(360.0, MediaQuery.sizeOf(context).width - 48);

    Widget painel = RepaintBoundary(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.aoFechar,
        },
        child: Focus(
          focusNode: _foco,
          autofocus: true,
          child: Container(
            decoration: BoxDecoration(
              color: c.elevada,
              border: Border(left: BorderSide(color: c.linha)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 30,
                  offset: Offset(-6, 0),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 10, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.titulo,
                          style: TextStyle(
                            fontFamily: fonteDisplay,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -.3,
                            color: c.tinta,
                          ),
                        ),
                      ),
                      BotaoIcone(
                        icone: Icons.close_rounded,
                        dica: 'Fechar',
                        onTap: widget.aoFechar,
                      ),
                    ],
                  ),
                ),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ),
      ),
    );
    painel = reduzir
        ? FadeTransition(opacity: _curva, child: painel)
        : SlideTransition(position: _deslize, child: painel);

    // Fechada: fora da tela e sem relógio, mas com o estado guardado.
    return Offstage(
      offstage: fechada,
      child: TickerMode(
        enabled: !fechada,
        child: IgnorePointer(
          ignoring: !widget.aberta,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: widget.aoFechar,
                  child: FadeTransition(
                    opacity: _curva,
                    child: ColoredBox(color: c.veu),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: largura,
                child: painel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
