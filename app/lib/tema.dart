import 'package:flutter/material.dart';

/// Cores do Neatly. Névoa azulada, tinta azul-marinho e um menta que só
/// aparece no que importa (o botão Organizar e as pastas novas).
@immutable
class Cores extends ThemeExtension<Cores> {
  const Cores({
    required this.fundo,
    required this.superficie,
    required this.elevada,
    required this.tinta,
    required this.suave,
    required this.fraca,
    required this.linha,
    required this.menta,
    required this.sobreMenta,
    required this.mentaFundo,
    required this.mentaTinta,
    required this.aviso,
    required this.avisoFundo,
    required this.veu,
  });

  static const claro = Cores(
    fundo: Color(0xFFEEF1F4),
    superficie: Color(0xB8FFFFFF),
    elevada: Color(0xFFFFFFFF),
    tinta: Color(0xFF17202B),
    suave: Color(0xFF566173),
    fraca: Color(0xFF6F7A88),
    linha: Color(0xFFDCE1E7),
    menta: Color(0xFF5FD4A8),
    sobreMenta: Color(0xFF06291D),
    mentaFundo: Color(0xFFDDF4EA),
    mentaTinta: Color(0xFF0E6B4C),
    aviso: Color(0xFF8A5A0B),
    avisoFundo: Color(0xFFFBF0DC),
    veu: Color(0x33101820),
  );

  static const escuro = Cores(
    fundo: Color(0xFF11151B),
    superficie: Color(0xB01A2028),
    elevada: Color(0xFF1E252E),
    tinta: Color(0xFFE9EEF3),
    suave: Color(0xFFA0AAB7),
    fraca: Color(0xFF87929F),
    linha: Color(0xFF2A323D),
    menta: Color(0xFF5FD4A8),
    sobreMenta: Color(0xFF06291D),
    mentaFundo: Color(0xFF16382C),
    mentaTinta: Color(0xFF7FE0BB),
    aviso: Color(0xFFE9BC6A),
    avisoFundo: Color(0xFF3A2F18),
    veu: Color(0x66000000),
  );

  final Color fundo;

  /// Cartões sobre o Mica (translúcida).
  final Color superficie;

  /// Menus e gavetas (opaca).
  final Color elevada;
  final Color tinta;
  final Color suave;
  final Color fraca;
  final Color linha;
  final Color menta;
  final Color sobreMenta;
  final Color mentaFundo;
  final Color mentaTinta;
  final Color aviso;
  final Color avisoFundo;
  final Color veu;

  static Cores de(BuildContext c) => Theme.of(c).extension<Cores>()!;

  @override
  Cores copyWith() => this;

  @override
  Cores lerp(Cores? outra, double t) => t < .5 ? this : (outra ?? this);
}

/// Cor de cada tipo de arquivo nas folhas da pilha.
const coresTipo = <String, Color>{
  'Imagens': Color(0xFFE8906F),
  'Documentos': Color(0xFF6E9BE0),
  'Vídeos': Color(0xFFA387E0),
  'Áudios': Color(0xFFE07FA8),
  'Planilhas': Color(0xFF6FBF7E),
  'Apresentações': Color(0xFFE3A35A),
  'Instaladores': Color(0xFF7DB8A5),
  'Compactados': Color(0xFFD9AE5F),
  'Código': Color(0xFF8C9BB0),
};
const corTipoOutros = Color(0xFF9AA3AE);

/// Curvas e tempos (todo o app usa estes, nada solto).
abstract final class Mov {
  /// Entrada e resposta a toque: começa rápido.
  static const saida = Cubic(0.23, 1, 0.32, 1);

  /// Coisa que se move na tela.
  static const meio = Cubic(0.77, 0, 0.175, 1);

  /// Gavetas.
  static const gaveta = Cubic(0.32, 0.72, 0, 1);

  static const toque = Duration(milliseconds: 140);
  static const rapido = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 240);
  static const gavetaDur = Duration(milliseconds: 320);
  static const pilha = Duration(milliseconds: 720);

  /// Windows com "efeitos de animação" desligados: só esmaecer, curto.
  static bool reduzir(BuildContext c) => MediaQuery.disableAnimationsOf(c);
}

const fonteTexto = 'Segoe UI Variable Text';
const fonteDisplay = 'Segoe UI Variable Display';
const _fallback = ['Segoe UI', 'Arial'];

ThemeData tema(Brightness b) {
  final c = b == Brightness.dark ? Cores.escuro : Cores.claro;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    fontFamily: fonteTexto,
    fontFamilyFallback: _fallback,
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.menta,
      brightness: b,
      primary: c.mentaTinta,
      surface: c.elevada,
    ),
    splashFactory: NoSplash.splashFactory,
    hoverColor: c.tinta.withValues(alpha: .05),
    highlightColor: Colors.transparent,
    focusColor: c.menta.withValues(alpha: .25),
    extensions: [c],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: c.tinta,
      displayColor: c.tinta,
      fontFamily: fonteTexto,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: c.tinta,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(
        color: c.fundo,
        fontSize: 12,
        fontFamily: fonteTexto,
      ),
    ),
  );
}
