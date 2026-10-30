import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tema.dart';

/// A marca do Neatly: folhas jogadas de qualquer jeito que, ao organizar,
/// se endireitam e descem para dentro de uma pasta.
///
/// [ordem] vai de 0 (bagunça) a 1 (tudo na pasta). Passar o mouse no botão
/// Organizar dá uma prévia (as folhas se ajeitam um pouco). [pensando]
/// embaralha devagar enquanto o Claude lê.
class Pilha extends StatefulWidget {
  const Pilha({
    super.key,
    required this.cores,
    required this.arrumado,
    this.foco = false,
    this.pensando = false,
  });

  /// Cor de cada folha visível (até 6), na ordem de cima para baixo.
  final List<Color> cores;
  final bool arrumado;
  final bool foco;
  final bool pensando;

  @override
  State<Pilha> createState() => _PilhaState();
}

class _PilhaState extends State<Pilha> with TickerProviderStateMixin {
  late final AnimationController _ordem = AnimationController(
    vsync: this,
    duration: Mov.pilha,
    value: widget.arrumado ? 1 : 0,
  );
  late final AnimationController _pensar = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late List<Color> _cores = _comMinimo(widget.cores);

  static List<Color> _comMinimo(List<Color> c) =>
      c.isEmpty ? const [corTipoOutros, corTipoOutros, corTipoOutros] : c;

  double get _alvo => widget.arrumado ? 1 : (widget.foco ? .22 : 0);

  @override
  void didUpdateWidget(Pilha antiga) {
    super.didUpdateWidget(antiga);
    // Ao arrumar, as folhas que estavam na tela são as que entram na pasta.
    if (!widget.arrumado) _cores = _comMinimo(widget.cores);
    final reduzir = Mov.reduzir(context);
    if (_alvo != _ordem.value) {
      final indoArrumar = widget.arrumado != antiga.arrumado;
      _ordem.animateTo(
        _alvo,
        duration: reduzir
            ? Duration.zero
            : indoArrumar
            ? Mov.pilha
            : Mov.base,
        curve: indoArrumar ? Mov.meio : Mov.saida,
      );
    }
    if (widget.pensando && !reduzir) {
      if (!_pensar.isAnimating) _pensar.repeat();
    } else if (_pensar.isAnimating) {
      _pensar.animateTo(1, duration: Mov.base).then((_) => _pensar.value = 0);
    }
  }

  @override
  void dispose() {
    _ordem.dispose();
    _pensar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: 220,
        height: 156,
        child: AnimatedBuilder(
          animation: Listenable.merge([_ordem, _pensar]),
          builder: (_, _) => CustomPaint(
            painter: _Pintor(
              cores: _cores,
              ordem: _ordem.value,
              fase: _pensar.value,
              pensando: _pensar.isAnimating,
              papel: c.elevada,
              linha: c.linha,
              tinta: c.tinta,
              pasta: c.menta,
            ),
          ),
        ),
      ),
    );
  }
}

/// Onde cada folha cai na bagunça: (dx, dy, graus).
const _bagunca = [
  (-38.0, 6.0, -13.0),
  (30.0, -4.0, 11.0),
  (-6.0, -14.0, -4.0),
  (46.0, 16.0, 19.0),
  (-58.0, 22.0, -21.0),
  (8.0, 18.0, 7.0),
];

class _Pintor extends CustomPainter {
  _Pintor({
    required this.cores,
    required this.ordem,
    required this.fase,
    required this.pensando,
    required this.papel,
    required this.linha,
    required this.tinta,
    required this.pasta,
  });

  final List<Color> cores;
  final double ordem;
  final double fase;
  final bool pensando;
  final Color papel;
  final Color linha;
  final Color tinta;
  final Color pasta;

  static const _folha = Size(54, 68);

  @override
  void paint(Canvas canvas, Size size) {
    final centro = Offset(size.width / 2, size.height / 2);
    // A pasta surge na segunda metade do movimento.
    final pastaT = Curves.easeOut.transform(((ordem - .35) / .65).clamp(0, 1));
    final topoPasta = centro.dy - 22;
    final larguraPasta = 138.0;
    final alturaPasta = 84.0;
    final retPasta = Rect.fromCenter(
      center: Offset(centro.dx, topoPasta + alturaPasta / 2),
      width: larguraPasta,
      height: alturaPasta,
    );

    if (pastaT > 0) _fundoPasta(canvas, retPasta, pastaT);

    final n = math.min(cores.length, _bagunca.length);
    for (var i = n - 1; i >= 0; i--) {
      final (bx, by, bg) = _bagunca[i];
      // Arrumada: em pé dentro da pasta, uma atrás da outra.
      final ax = (i - (n - 1) / 2) * 9.0;
      final ay = topoPasta + 14 - i * 3.0;
      final ag = (i.isEven ? -1 : 1) * 1.5;
      // Cada folha anda com um atraso pequeno: entram em sequência.
      final t = Mov.meio.transform(
        ((ordem * (1 + n * .08)) - i * .08).clamp(0.0, 1.0),
      );
      var dx = centro.dx + bx + (ax - bx) * t;
      var dy = centro.dy + by + (ay - centro.dy - by) * t;
      var graus = bg + (ag - bg) * t;
      if (pensando) {
        final onda = math.sin((fase + i / n) * math.pi * 2);
        dx += onda * 4;
        dy += math.cos((fase + i / n) * math.pi * 2) * 2.5;
        graus += onda * 3;
      }
      _desenharFolha(canvas, Offset(dx, dy), graus * math.pi / 180, cores[i]);
    }

    if (pastaT > 0) _frentePasta(canvas, retPasta, pastaT);
  }

  void _desenharFolha(Canvas canvas, Offset centro, double angulo, Color cor) {
    canvas.save();
    canvas.translate(centro.dx, centro.dy);
    canvas.rotate(angulo);
    final r = Rect.fromCenter(
      center: Offset.zero,
      width: _folha.width,
      height: _folha.height,
    );
    const dobra = 13.0;
    final corpo = Path()
      ..moveTo(r.left + 6, r.top)
      ..lineTo(r.right - dobra, r.top)
      ..lineTo(r.right, r.top + dobra)
      ..lineTo(r.right, r.bottom - 6)
      ..quadraticBezierTo(r.right, r.bottom, r.right - 6, r.bottom)
      ..lineTo(r.left + 6, r.bottom)
      ..quadraticBezierTo(r.left, r.bottom, r.left, r.bottom - 6)
      ..lineTo(r.left, r.top + 6)
      ..quadraticBezierTo(r.left, r.top, r.left + 6, r.top)
      ..close();
    canvas.drawShadow(corpo, Colors.black, 3, false);
    canvas.drawPath(corpo, Paint()..color = papel);
    canvas.drawPath(
      corpo,
      Paint()
        ..color = linha
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Dobra do canto.
    canvas.drawPath(
      Path()
        ..moveTo(r.right - dobra, r.top)
        ..lineTo(r.right - dobra, r.top + dobra - 3)
        ..quadraticBezierTo(
          r.right - dobra,
          r.top + dobra,
          r.right - dobra + 3,
          r.top + dobra,
        )
        ..lineTo(r.right, r.top + dobra)
        ..close(),
      Paint()..color = linha,
    );
    // Faixa do tipo e linhas de "texto".
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left + 8, r.top + 10, 18, 18),
        const Radius.circular(5),
      ),
      Paint()..color = cor,
    );
    final traco = Paint()
      ..color = tinta.withValues(alpha: .12)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 3; k++) {
      final y = r.top + 38 + k * 8.0;
      canvas.drawLine(
        Offset(r.left + 9, y),
        Offset(r.right - (k == 2 ? 22 : 10), y),
        traco,
      );
    }
    canvas.restore();
  }

  void _fundoPasta(Canvas canvas, Rect r, double t) {
    final cor = Color.lerp(pasta, Colors.black, .18)!.withValues(alpha: t);
    final aba = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(r.left, r.top - 12, 58, 24),
          const Radius.circular(8),
        ),
      );
    canvas.drawPath(aba, Paint()..color = cor);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(12)),
      Paint()..color = cor,
    );
  }

  void _frentePasta(Canvas canvas, Rect r, double t) {
    // A frente sobe de baixo: as folhas parecem cair dentro dela.
    final desloc = (1 - t) * 18;
    final frente = Rect.fromLTRB(
      r.left - 4,
      r.top + 26 + desloc,
      r.right + 4,
      r.bottom + 2 + desloc,
    );
    canvas.drawShadow(
      Path()
        ..addRRect(RRect.fromRectAndRadius(frente, const Radius.circular(12))),
      Colors.black,
      4 * t,
      false,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(frente, const Radius.circular(12)),
      Paint()..color = pasta.withValues(alpha: t),
    );
    // Brilho sutil na borda de cima da frente.
    canvas.drawLine(
      Offset(frente.left + 12, frente.top + 1.5),
      Offset(frente.right - 12, frente.top + 1.5),
      Paint()
        ..color = Colors.white.withValues(alpha: .35 * t)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_Pintor o) =>
      o.ordem != ordem ||
      o.fase != fase ||
      o.pensando != pensando ||
      o.cores != cores ||
      o.papel != papel;
}
