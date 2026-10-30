import 'package:flutter/material.dart';
import 'package:neatly_core/neatly_core.dart';

import '../estado.dart';
import '../tema.dart';
import 'comum.dart';
import 'pilha.dart';

/// Cor da folha de cada arquivo (pela pasta genérica do tipo).
List<Color> coresDosArquivos(List<ArquivoSolto> arquivos) => [
  for (final a in arquivos.take(6))
    coresTipo[destinoScript(a).split('/').first] ?? corTipoOutros,
];

String quando(DateTime d, {DateTime? agora}) {
  final hoje = agora ?? DateTime.now();
  final dia = DateTime(d.year, d.month, d.day);
  final diff = DateTime(hoje.year, hoje.month, hoje.day).difference(dia).inDays;
  final hora =
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (diff == 0) return 'hoje às $hora';
  if (diff == 1) return 'ontem às $hora';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} às $hora';
}

/// Tela principal: a pilha, quantos arquivos estão soltos e o Organizar.
class Inicio extends StatefulWidget {
  const Inicio({super.key, required this.estado, required this.abrirAgenda});

  final Estado estado;
  final VoidCallback abrirAgenda;

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  bool _foco = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.estado;
    final n = e.varredura.soltos.length;
    final pensando = e.fase == Fase.planejando;
    final movendo = e.fase == Fase.movendo;
    final vazio = n == 0 && !pensando;
    final cores = movendo
        ? coresDosArquivos(
            e.plano?.movimentos.map((m) => m.arquivo).toList() ?? const [],
          )
        : coresDosArquivos(e.varredura.soltos);

    // Os Spacers distribuem a sobra; se a janela ficar baixa demais, rola
    // em vez de estourar.
    return LayoutBuilder(
      builder: (context, caixa) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: caixa.maxHeight),
          child: IntrinsicHeight(
            child: _coluna(e, cores, pensando, vazio, movendo),
          ),
        ),
      ),
    );
  }

  Widget _coluna(
    Estado e,
    List<Color> cores,
    bool pensando,
    bool vazio,
    bool movendo,
  ) {
    return Column(
      children: [
        const Spacer(flex: 3),
        Pilha(
          cores: cores,
          arrumado: vazio || movendo,
          foco: _foco,
          pensando: pensando,
        ),
        const SizedBox(height: 22),
        // Texto de várias linhas fica centrado e longe das bordas, mesmo na
        // janela no tamanho mínimo.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AnimatedSwitcher(
              duration: Mov.base,
              switchInCurve: Mov.saida,
              switchOutCurve: Curves.easeOut,
              transitionBuilder: _subirEsmaecer,
              layoutBuilder: (atual, anteriores) => Stack(
                alignment: Alignment.topCenter,
                children: [...anteriores, ?atual],
              ),
              child: pensando
                  ? _Pensando(key: const ValueKey('pensando'), estado: e)
                  : vazio || movendo
                  ? _Vazio(key: const ValueKey('vazio'), estado: e)
                  : _Contagem(key: const ValueKey('contagem'), estado: e),
            ),
          ),
        ),
        const SizedBox(height: 26),
        SizedBox(
          height: 52,
          child: AnimatedSwitcher(
            duration: Mov.base,
            switchInCurve: Mov.saida,
            transitionBuilder: _subirEsmaecer,
            child: pensando
                ? BotaoTexto(
                    key: const ValueKey('cancelar'),
                    texto: 'Cancelar',
                    onTap: e.cancelar,
                  )
                : vazio || movendo
                ? BotaoTexto(
                    key: const ValueKey('abrir'),
                    texto: 'Abrir ${e.nomePasta}',
                    icone: Icons.folder_open_rounded,
                    onTap: e.abrirPasta,
                  )
                : BotaoPrincipal(
                    key: const ValueKey('organizar'),
                    texto: 'Organizar',
                    grande: true,
                    onHover: (v) => setState(() => _foco = v),
                    onTap: () {
                      setState(() => _foco = false);
                      e.organizar();
                    },
                  ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: AnimatedSwitcher(
            duration: Mov.base,
            switchInCurve: Mov.saida,
            transitionBuilder: _subirEsmaecer,
            child: e.aviso != null && !pensando
                ? Padding(
                    key: const ValueKey('aviso'),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      e.aviso!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Cores.de(context).aviso,
                      ),
                    ),
                  )
                : pensando ||
                      movendo ||
                      e.ajustes.modo != Modo.claude ||
                      !e.claudeInstalado
                ? const SizedBox.shrink(key: ValueKey('nada'))
                : BotaoTexto(
                    key: const ValueKey('tudo'),
                    texto: 'Reorganizar tudo',
                    icone: Icons.auto_awesome_rounded,
                    onTap: () => e.organizar(tudo: true),
                  ),
          ),
        ),
        const Spacer(flex: 2),
        _LinhaAgenda(estado: e, onTap: widget.abrirAgenda),
        const SizedBox(height: 18),
      ],
    );
  }
}

Widget _subirEsmaecer(Widget filho, Animation<double> a) => FadeTransition(
  opacity: a,
  child: SlideTransition(
    position: Tween(begin: const Offset(0, .12), end: Offset.zero).animate(a),
    child: filho,
  ),
);

class _Contagem extends StatelessWidget {
  const _Contagem({super.key, required this.estado});

  final Estado estado;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final n = estado.varredura.soltos.length;
    final recentes = estado.varredura.recentes;
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: n.toDouble()),
          duration: Mov.pilha,
          curve: Mov.saida,
          builder: (_, v, _) => Text(
            '${v.round()}',
            style: TextStyle(
              fontFamily: fonteDisplay,
              fontSize: 64,
              height: 1,
              fontWeight: FontWeight.w600,
              letterSpacing: -2.5,
              color: c.tinta,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${n == 1 ? 'arquivo solto' : 'arquivos soltos'} em ${estado.nomePasta}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: c.suave, height: 1.4),
        ),
        if (recentes > 0) ...[
          const SizedBox(height: 4),
          Text(
            recentes == 1
                ? '1 baixado agora fica para depois'
                : '$recentes baixados agora ficam para depois',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: c.fraca, height: 1.4),
          ),
        ],
      ],
    );
  }
}

class _Vazio extends StatelessWidget {
  const _Vazio({super.key, required this.estado});

  final Estado estado;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final ultima = estado.rodadas.where((r) => !r.desfeita).firstOrNull;
    return Column(
      children: [
        Text(
          estado.fase == Fase.movendo ? 'Guardando' : 'Tudo no lugar',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: fonteDisplay,
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w600,
            letterSpacing: -.6,
            color: c.tinta,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          estado.fase == Fase.movendo
              ? 'Guardando os arquivos…'
              : ultima == null
              ? 'Nenhum arquivo solto em ${estado.nomePasta}'
              : 'Última arrumação ${quando(ultima.quando)}, '
                    '${ultima.mudancas.length} ${ultima.mudancas.length == 1 ? 'arquivo' : 'arquivos'}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14.5, color: c.suave, height: 1.4),
        ),
      ],
    );
  }
}

class _Pensando extends StatelessWidget {
  const _Pensando({super.key, required this.estado});

  final Estado estado;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final n = estado.varredura.soltos.length;
    final claude = estado.ajustes.modo == Modo.claude;
    final tudo = estado.reorganizando;
    return Column(
      children: [
        Text(
          tudo
              ? 'Repensando a pasta'
              : claude
              ? 'Lendo os arquivos'
              : 'Separando por tipo',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: fonteDisplay,
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w600,
            letterSpacing: -.6,
            color: c.tinta,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tudo
              ? 'O Claude está olhando tudo em ${estado.nomePasta}, '
                    'pastas inclusive. Pode levar alguns minutos…'
              : claude
              ? 'O Claude está decidindo as pastas de $n ${n == 1 ? 'arquivo' : 'arquivos'}…'
              : 'Montando a prévia…',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14.5, color: c.suave, height: 1.4),
        ),
      ],
    );
  }
}

class _LinhaAgenda extends StatelessWidget {
  const _LinhaAgenda({required this.estado, required this.onTap});

  final Estado estado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final a = estado.ajustes.agendamento;
    return Pressionavel(
      onTap: onTap,
      rotulo: 'Arrumação automática',
      raio: 999,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              a.ativo
                  ? Icons.schedule_rounded
                  : Icons.do_not_disturb_on_outlined,
              size: 15,
              color: c.fraca,
            ),
            const SizedBox(width: 7),
            Text(
              a.ativo
                  ? 'Arruma sozinho todo dia às ${a.horario}'
                  : 'Arrumação automática desligada',
              style: TextStyle(fontSize: 13, color: c.fraca),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 16, color: c.fraca),
          ],
        ),
      ),
    );
  }
}
