import 'package:flutter/material.dart';

import '../tema.dart';

/// Qualquer coisa clicável: realce ao passar o mouse e leve encolhida ao
/// apertar, para a interface responder na hora.
class Pressionavel extends StatefulWidget {
  const Pressionavel({
    super.key,
    required this.child,
    required this.onTap,
    this.rotulo,
    this.raio = 10,
    this.realce = true,
    this.escala = .97,
    this.onHover,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? rotulo;
  final double raio;
  final bool realce;
  final double escala;
  final ValueChanged<bool>? onHover;

  @override
  State<Pressionavel> createState() => _PressionavelState();
}

class _PressionavelState extends State<Pressionavel> {
  bool _sobre = false;
  bool _apertado = false;
  bool _foco = false;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    return Semantics(
      button: true,
      label: widget.rotulo,
      child: FocusableActionDetector(
        onShowFocusHighlight: (v) => setState(() => _foco = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onTap?.call(),
          ),
        },
        child: MouseRegion(
          cursor: widget.onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onEnter: (_) {
            setState(() => _sobre = true);
            widget.onHover?.call(true);
          },
          onExit: (_) {
            setState(() {
              _sobre = false;
              _apertado = false;
            });
            widget.onHover?.call(false);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _apertado = true),
            onTapCancel: () => setState(() => _apertado = false),
            onTapUp: (_) => setState(() => _apertado = false),
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: _apertado ? widget.escala : 1,
              duration: Mov.toque,
              curve: Mov.saida,
              child: AnimatedContainer(
                duration: Mov.rapido,
                curve: Curves.ease,
                decoration: BoxDecoration(
                  color: widget.realce && _sobre
                      ? c.tinta.withValues(alpha: .06)
                      : c.tinta.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(widget.raio),
                  border: Border.all(
                    color: _foco ? c.realce : c.realce.withValues(alpha: 0),
                    width: 2,
                  ),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// O único botão cheio de cada tela.
class BotaoPrincipal extends StatefulWidget {
  const BotaoPrincipal({
    super.key,
    required this.texto,
    required this.onTap,
    this.onHover,
    this.grande = false,
  });

  final String texto;
  final VoidCallback onTap;
  final ValueChanged<bool>? onHover;
  final bool grande;

  @override
  State<BotaoPrincipal> createState() => _BotaoPrincipalState();
}

class _BotaoPrincipalState extends State<BotaoPrincipal> {
  bool _sobre = false;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    return Pressionavel(
      onTap: widget.onTap,
      rotulo: widget.texto,
      realce: false,
      raio: 999,
      onHover: (v) {
        setState(() => _sobre = v);
        widget.onHover?.call(v);
      },
      child: AnimatedContainer(
        duration: Mov.rapido,
        curve: Curves.ease,
        padding: EdgeInsets.symmetric(
          horizontal: widget.grande ? 34 : 22,
          vertical: widget.grande ? 14 : 10,
        ),
        decoration: BoxDecoration(
          color: _sobre ? Color.lerp(c.menta, Colors.white, .12) : c.menta,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: c.menta.withValues(alpha: _sobre ? .45 : .28),
              blurRadius: _sobre ? 22 : 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          widget.texto,
          style: TextStyle(
            color: c.sobreMenta,
            fontSize: widget.grande ? 16 : 14,
            fontWeight: FontWeight.w600,
            letterSpacing: .1,
          ),
        ),
      ),
    );
  }
}

/// Botão de texto, sem fundo (ações secundárias).
class BotaoTexto extends StatelessWidget {
  const BotaoTexto({
    super.key,
    required this.texto,
    required this.onTap,
    this.icone,
    this.cor,
  });

  final String texto;
  final VoidCallback? onTap;
  final IconData? icone;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final cor = this.cor ?? c.suave;
    return Pressionavel(
      onTap: onTap,
      rotulo: texto,
      raio: 999,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icone != null) ...[
              Icon(icone, size: 16, color: cor),
              const SizedBox(width: 6),
            ],
            Text(
              texto,
              style: TextStyle(
                color: cor,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ícone da barra de cima, com dica.
class BotaoIcone extends StatelessWidget {
  const BotaoIcone({
    super.key,
    required this.icone,
    required this.dica,
    required this.onTap,
    this.tamanho = 18,
    this.cor,
  });

  final IconData icone;
  final String dica;
  final VoidCallback onTap;
  final double tamanho;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    return Tooltip(
      message: dica,
      child: Pressionavel(
        onTap: onTap,
        rotulo: dica,
        raio: 8,
        escala: .92,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icone, size: tamanho, color: cor ?? c.suave),
        ),
      ),
    );
  }
}

/// Selo pequeno ("nova", "agendada").
class Selo extends StatelessWidget {
  const Selo(this.texto, {super.key, this.fundo, this.cor});

  final String texto;
  final Color? fundo;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(
        color: fundo ?? c.mentaFundo,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: cor ?? c.mentaTinta,
          height: 1.3,
        ),
      ),
    );
  }
}

/// Entrada com atraso: esmaece e sobe 8px. Para listas em cascata.
class Entrada extends StatelessWidget {
  const Entrada({super.key, required this.child, this.atraso = 0});

  final Widget child;

  /// Posição na cascata (cada uma soma 40ms, até um teto).
  final int atraso;

  @override
  Widget build(BuildContext context) {
    final reduzir = Mov.reduzir(context);
    final espera = (atraso.clamp(0, 10) * 40);
    final total = Mov.base.inMilliseconds + espera;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: reduzir ? 120 : total),
      builder: (_, v, filho) {
        final t = reduzir
            ? v
            : Mov.saida.transform(
                ((v * total - espera) / Mov.base.inMilliseconds).clamp(0, 1),
              );
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, reduzir ? 0 : (1 - t) * 8),
            child: filho,
          ),
        );
      },
      child: child,
    );
  }
}
