import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:neatly_core/neatly_core.dart';

import '../estado.dart';
import '../tema.dart';
import 'ajustes_ui.dart';
import 'barra.dart';
import 'comum.dart';
import 'gaveta.dart';
import 'historico_ui.dart';
import 'inicio.dart';
import 'previa.dart';

/// Tema escolhido nos ajustes, já resolvido: Sistema vira o do Windows.
bool temaEscuro(Tema t) => switch (t) {
  Tema.claro => false,
  Tema.escuro => true,
  Tema.sistema =>
    WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark,
};

/// O Mica é pintado pelo Windows: segue a escolha do app, senão fica fundo
/// escuro com cartão claro.
Future<void> aplicarMica(bool escuro) =>
    acrylic.Window.setEffect(effect: acrylic.WindowEffect.mica, dark: escuro);

class NeatlyApp extends StatefulWidget {
  const NeatlyApp({super.key, required this.estado, this.mica = aplicarMica});

  final Estado estado;
  final Future<void> Function(bool escuro) mica;

  @override
  State<NeatlyApp> createState() => _NeatlyAppState();
}

class _NeatlyAppState extends State<NeatlyApp> with WidgetsBindingObserver {
  late bool _escuro;

  @override
  void initState() {
    super.initState();
    // Igual ao Mica que o main aplicou ao abrir a janela.
    _escuro = temaEscuro(widget.estado.ajustes.tema);
    WidgetsBinding.instance.addObserver(this);
    widget.estado.addListener(_sincronizarMica);
  }

  @override
  void dispose() {
    widget.estado.removeListener(_sincronizarMica);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Em Sistema, a troca do Windows chega aqui com o app aberto.
  @override
  void didChangePlatformBrightness() => _sincronizarMica();

  void _sincronizarMica() {
    final escuro = temaEscuro(widget.estado.ajustes.tema);
    if (escuro == _escuro) return;
    _escuro = escuro;
    widget.mica(escuro);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.estado,
      builder: (_, _) => MaterialApp(
        title: 'Neatly',
        debugShowCheckedModeBanner: false,
        theme: tema(Brightness.light),
        darkTheme: tema(Brightness.dark),
        themeMode: switch (widget.estado.ajustes.tema) {
          Tema.sistema => ThemeMode.system,
          Tema.claro => ThemeMode.light,
          Tema.escuro => ThemeMode.dark,
        },
        themeAnimationDuration: Mov.tema,
        themeAnimationCurve: Curves.easeOut,
        home: Casca(estado: widget.estado),
      ),
    );
  }
}

enum _Painel { nenhum, historico, ajustes }

/// Janela inteira: barra, tela principal ou prévia, gavetas e o aviso.
class Casca extends StatefulWidget {
  const Casca({super.key, required this.estado});

  final Estado estado;

  @override
  State<Casca> createState() => _CascaState();
}

class _CascaState extends State<Casca> {
  _Painel _painel = _Painel.nenhum;
  _Painel _ultimoPainel = _Painel.historico;

  void _abrir(_Painel p) => setState(() {
    _painel = p;
    _ultimoPainel = p;
  });

  void _fechar() => setState(() => _painel = _Painel.nenhum);

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final e = widget.estado;
    final naPrevia = e.fase == Fase.previa;
    final reduzir = Mov.reduzir(context);

    return Scaffold(
      body: DecoratedBox(
        // Por cima do Mica: um véu leve da cor de fundo, para o texto
        // ter contraste em qualquer papel de parede.
        decoration: BoxDecoration(color: c.fundo.withValues(alpha: .55)),
        child: Stack(
          children: [
            Column(
              children: [
                Barra(
                  estado: e,
                  abrirHistorico: () => _abrir(_Painel.historico),
                  abrirAjustes: () => _abrir(_Painel.ajustes),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      // A tela principal fica montada sob a prévia: ao mover,
                      // a mesma pilha é a que entra na pasta.
                      IgnorePointer(
                        ignoring: naPrevia,
                        child: AnimatedOpacity(
                          opacity: naPrevia ? 0 : 1,
                          duration: Mov.base,
                          curve: Mov.saida,
                          child: AnimatedScale(
                            scale: naPrevia && !reduzir ? .96 : 1,
                            duration: Mov.base,
                            curve: Mov.saida,
                            child: Inicio(
                              estado: e,
                              abrirAgenda: () => _abrir(_Painel.ajustes),
                            ),
                          ),
                        ),
                      ),
                      IgnorePointer(
                        ignoring: !naPrevia,
                        child: AnimatedOpacity(
                          opacity: naPrevia ? 1 : 0,
                          duration: naPrevia ? Mov.base : Mov.rapido,
                          curve: Mov.saida,
                          child: AnimatedSlide(
                            offset: naPrevia || reduzir
                                ? Offset.zero
                                : const Offset(0, .04),
                            duration: Mov.base,
                            curve: Mov.saida,
                            child: naPrevia
                                ? Previa(estado: e)
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 52,
              child: AvisoGuardado(estado: e),
            ),
            Positioned.fill(
              child: Gaveta(
                aberta: _painel != _Painel.nenhum,
                titulo:
                    (_painel == _Painel.nenhum ? _ultimoPainel : _painel) ==
                        _Painel.historico
                    ? 'Histórico'
                    : 'Ajustes',
                aoFechar: _fechar,
                child:
                    (_painel == _Painel.nenhum ? _ultimoPainel : _painel) ==
                        _Painel.historico
                    ? ConteudoHistorico(estado: e)
                    : ConteudoAjustes(estado: e),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "12 arquivos guardados · Desfazer", que sobe de baixo depois de mover e
/// some sozinho (o tempo pausa com o mouse em cima).
class AvisoGuardado extends StatefulWidget {
  const AvisoGuardado({super.key, required this.estado});

  final Estado estado;

  @override
  State<AvisoGuardado> createState() => _AvisoGuardadoState();
}

class _AvisoGuardadoState extends State<AvisoGuardado> {
  Timer? _tempo;
  String? _idMostrado;
  Rodada? _rodada;
  int? _voltaram;

  static const _duracao = Duration(seconds: 8);

  void _contar() {
    _tempo?.cancel();
    _tempo = Timer(_duracao, _sumir);
  }

  void _sumir() {
    _tempo?.cancel();
    if (!mounted) return;
    setState(() => _rodada = null);
    widget.estado.esquecerUltima();
  }

  @override
  void didUpdateWidget(AvisoGuardado antiga) {
    super.didUpdateWidget(antiga);
    _sincronizar();
  }

  @override
  void initState() {
    super.initState();
    _sincronizar();
  }

  void _sincronizar() {
    final u = widget.estado.ultima;
    if (u != null && u.id != _idMostrado) {
      _idMostrado = u.id;
      _rodada = u;
      _voltaram = null;
      _contar();
    }
  }

  @override
  void dispose() {
    _tempo?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final r = _rodada;
    final visivel = r != null;
    final n = r?.mudancas.length ?? 0;
    final texto = _voltaram != null
        ? '$_voltaram ${_voltaram == 1 ? 'arquivo voltou' : 'arquivos voltaram'} para o lugar'
        : '$n ${n == 1 ? 'arquivo guardado' : 'arquivos guardados'}'
              '${r != null && r.falhas > 0 ? ', ${r.falhas} em uso ficaram' : ''}';

    return IgnorePointer(
      ignoring: !visivel,
      child: AnimatedSlide(
        offset: visivel ? Offset.zero : const Offset(0, .6),
        duration: visivel ? Mov.base : Mov.rapido,
        curve: Mov.saida,
        child: AnimatedOpacity(
          opacity: visivel ? 1 : 0,
          duration: visivel ? Mov.base : Mov.rapido,
          child: Center(
            child: MouseRegion(
              onEnter: (_) => _tempo?.cancel(),
              onExit: (_) => visivel ? _contar() : null,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                decoration: BoxDecoration(
                  color: c.tinta,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _voltaram != null
                          ? Icons.undo_rounded
                          : Icons.check_rounded,
                      size: 16,
                      color: c.mentaSobreTinta,
                    ),
                    const SizedBox(width: 8),
                    AnimatedSize(
                      duration: Mov.rapido,
                      curve: Mov.saida,
                      child: Text(
                        texto,
                        style: TextStyle(color: c.fundo, fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (_voltaram == null && r != null) ...[
                      BotaoTexto(
                        texto: 'Ver',
                        cor: c.fundo.withValues(alpha: .75),
                        onTap: () => widget.estado.abrirPasta(),
                      ),
                      BotaoTexto(
                        texto: 'Desfazer',
                        cor: c.mentaSobreTinta,
                        onTap: () {
                          final v = widget.estado.desfazerRodada(r);
                          setState(() => _voltaram = v);
                          _tempo?.cancel();
                          _tempo = Timer(const Duration(seconds: 3), _sumir);
                        },
                      ),
                    ] else
                      const SizedBox(width: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
