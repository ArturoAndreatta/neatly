import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:neatly_core/neatly_core.dart';
import 'package:window_manager/window_manager.dart';

import '../estado.dart';
import '../tema.dart';
import 'comum.dart';

/// Barra de cima: arrasta a janela, escolhe o modo e abre histórico e
/// ajustes. Substitui a barra do Windows.
class Barra extends StatelessWidget {
  const Barra({
    super.key,
    required this.estado,
    required this.abrirHistorico,
    required this.abrirAjustes,
  });

  final Estado estado;
  final VoidCallback abrirHistorico;
  final VoidCallback abrirAjustes;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    // Na janela estreita o aviso de versão vira só o ícone, para a marca
    // e os botões caberem sem apertar.
    final compacta = MediaQuery.sizeOf(context).width < 500;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Row(
                  children: [
                    Image.asset('assets/neatly-512.png', width: 18, height: 18),
                    const SizedBox(width: 9),
                    // Na janela estreita, com o aviso de versão, o nome cede
                    // o espaço: o ícone já diz que app é.
                    Flexible(
                      child: Text(
                        'Neatly',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                          fontFamily: fonteDisplay,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.tinta,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (estado.atualizacao != null) ...[
            _Atualizar(estado: estado, compacta: compacta),
            const SizedBox(width: 6),
          ],
          SeletorModo(
            modo: estado.ajustes.modo,
            avisoClaude: estado.faltaClaude,
            aoEscolher: estado.trocarModo,
          ),
          const SizedBox(width: 4),
          BotaoIcone(
            icone: Icons.history_rounded,
            dica: 'Histórico',
            onTap: abrirHistorico,
          ),
          BotaoIcone(
            icone: Icons.tune_rounded,
            dica: 'Ajustes',
            onTap: abrirAjustes,
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 18, color: c.linha),
          const SizedBox(width: 4),
          BotaoIcone(
            icone: Icons.remove_rounded,
            dica: 'Minimizar',
            onTap: windowManager.minimize,
          ),
          BotaoIcone(
            icone: Icons.close_rounded,
            dica: 'Fechar (a arrumação automática continua)',
            onTap: windowManager.close,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _Atualizar extends StatelessWidget {
  const _Atualizar({required this.estado, required this.compacta});

  final Estado estado;
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final b = estado.baixando;
    final rotulo = 'Atualizar para a versão ${estado.atualizacao!.versao}';
    return Entrada(
      child: Tooltip(
        message: compacta ? rotulo : '',
        child: Pressionavel(
          onTap: estado.atualizar,
          rotulo: rotulo,
          raio: 999,
          realce: false,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compacta ? 7 : 11,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: c.mentaFundo,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (b == null)
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 14,
                    color: c.mentaTinta,
                  )
                else
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      value: b == 0 ? null : b,
                      strokeWidth: 2,
                      color: c.mentaTinta,
                    ),
                  ),
                if (!compacta) ...[
                  const SizedBox(width: 6),
                  Text(
                    b == null
                        ? 'Versão ${estado.atualizacao!.versao}'
                        : 'Atualizando',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: c.mentaTinta,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData iconeModo(Modo m) =>
    m == Modo.claude ? Icons.auto_awesome_rounded : Icons.bolt_rounded;

String nomeModo(Modo m) => m == Modo.claude ? 'Claude' : 'Script';

String descricaoModo(Modo m) => m == Modo.claude
    ? 'Pastas por assunto, com o Haiku 5.5'
    : 'Por tipo de arquivo, na hora';

/// Cápsula com o modo atual; abre um menu que cresce a partir dela.
class SeletorModo extends StatefulWidget {
  const SeletorModo({
    super.key,
    required this.modo,
    required this.aoEscolher,
    this.avisoClaude,
  });

  final Modo modo;
  final ValueChanged<Modo> aoEscolher;
  final String? avisoClaude;

  @override
  State<SeletorModo> createState() => _SeletorModoState();
}

class _SeletorModoState extends State<SeletorModo>
    with SingleTickerProviderStateMixin {
  static const _larguraMenu = 292.0;
  static const _margem = 12.0;

  final _portal = OverlayPortalController();
  late final AnimationController _abrir = AnimationController(
    vsync: this,
    duration: Mov.rapido,
    reverseDuration: const Duration(milliseconds: 130),
  );

  void _alternar() {
    if (_abrir.status
        case AnimationStatus.forward || AnimationStatus.completed) {
      _fechar();
    } else {
      _portal.show();
      _abrir.forward();
    }
  }

  Future<void> _fechar() async {
    await _abrir.reverse();
    if (mounted) _portal.hide();
  }

  @override
  void dispose() {
    _abrir.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (context, info) {
        final alvo = MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        );
        final janela = info.overlaySize;
        // Alinhado pela direita do botão, mas sempre inteiro na janela.
        final largura = math.min(_larguraMenu, janela.width - 2 * _margem);
        final esquerda = (alvo.right - largura)
            .clamp(_margem, math.max(_margem, janela.width - _margem - largura))
            .toDouble();
        // A escala nasce do botão, não do canto do menu.
        final origem = Alignment(
          ((alvo.center.dx - esquerda) / largura * 2 - 1).clamp(-1.0, 1.0),
          -1,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _fechar,
                child: FadeTransition(
                  opacity: _abrir,
                  child: ColoredBox(
                    color: c.veu.withValues(alpha: c.veu.a * .6),
                  ),
                ),
              ),
            ),
            Positioned(
              left: esquerda,
              top: alvo.bottom + 8,
              width: largura,
              child: _Menu(
                animacao: _abrir,
                origem: origem,
                modo: widget.modo,
                avisoClaude: widget.avisoClaude,
                aoEscolher: (m) {
                  widget.aoEscolher(m);
                  _fechar();
                },
              ),
            ),
          ],
        );
      },
      child: Pressionavel(
        onTap: _alternar,
        rotulo: 'Modo: ${nomeModo(widget.modo)}',
        raio: 999,
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 5, 8, 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.linha),
            color: c.superficie,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: Mov.rapido,
                transitionBuilder: (w, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(
                    scale: Tween(begin: .8, end: 1.0).animate(a),
                    child: w,
                  ),
                ),
                child: Icon(
                  iconeModo(widget.modo),
                  key: ValueKey(widget.modo),
                  size: 15,
                  color: widget.modo == Modo.claude ? c.mentaTinta : c.suave,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedSize(
                duration: Mov.rapido,
                curve: Mov.saida,
                child: Text(
                  nomeModo(widget.modo),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: c.tinta,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              RotationTransition(
                turns: Tween(
                  begin: 0.0,
                  end: .5,
                ).animate(CurvedAnimation(parent: _abrir, curve: Mov.saida)),
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: c.fraca,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({
    required this.animacao,
    required this.origem,
    required this.modo,
    required this.aoEscolher,
    required this.avisoClaude,
  });

  final Animation<double> animacao;
  final Alignment origem;
  final Modo modo;
  final ValueChanged<Modo> aoEscolher;
  final String? avisoClaude;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final curva = CurvedAnimation(
      parent: animacao,
      curve: Mov.saida,
      reverseCurve: Curves.easeOut,
    );
    return FadeTransition(
      opacity: curva,
      child: ScaleTransition(
        alignment: origem,
        scale: Tween(begin: .95, end: 1.0).animate(curva),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: c.elevada,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.linha),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in Modo.values)
                  Pressionavel(
                    onTap: () => aoEscolher(m),
                    rotulo: nomeModo(m),
                    raio: 9,
                    escala: .98,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(
                              iconeModo(m),
                              size: 18,
                              color: m == Modo.claude ? c.mentaTinta : c.suave,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nomeModo(m),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: c.tinta,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  m == Modo.claude && avisoClaude != null
                                      ? avisoClaude!
                                      : descricaoModo(m),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color:
                                        m == Modo.claude && avisoClaude != null
                                        ? c.aviso
                                        : c.suave,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AnimatedOpacity(
                            opacity: m == modo ? 1 : 0,
                            duration: Mov.rapido,
                            child: Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: c.mentaTinta,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
