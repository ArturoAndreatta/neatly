import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema.dart';
import 'comum.dart';

/// Painel que desliza da direita sobre um véu. Esc ou clique fora fecha.
class Gaveta extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final reduzir = Mov.reduzir(context);
    return IgnorePointer(
      ignoring: !aberta,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: aberta ? 1 : 0),
        // Fechar é mais rápido que abrir: o sistema responde, não decide.
        duration: aberta ? Mov.gavetaDur : const Duration(milliseconds: 220),
        curve: Mov.gaveta,
        builder: (context, t, filho) {
          if (t == 0) return const SizedBox.shrink();
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: aoFechar,
                  child: ColoredBox(
                    color: c.veu.withValues(alpha: c.veu.a * t),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: 360,
                child: FractionalTranslation(
                  translation: Offset(reduzir ? 0 : 1 - t, 0),
                  child: Opacity(opacity: reduzir ? t : 1, child: filho),
                ),
              ),
            ],
          );
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): aoFechar,
          },
          child: Focus(
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
                            titulo,
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
                          onTap: aoFechar,
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
