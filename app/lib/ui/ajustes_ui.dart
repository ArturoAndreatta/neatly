import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:neatly_core/neatly_core.dart';

import '../estado.dart';
import '../tema.dart';
import 'barra.dart';
import 'comum.dart';

/// Conteúdo da gaveta de ajustes: pasta, arrumação automática e versão.
class ConteudoAjustes extends StatelessWidget {
  const ConteudoAjustes({super.key, required this.estado});

  final Estado estado;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final a = estado.ajustes.agendamento;
    final claude = estado.claudeInstalado;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
      children: [
        _Titulo('Pasta'),
        Row(
          children: [
            Icon(Icons.folder_rounded, size: 18, color: c.suave),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                estado.pasta,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: c.tinta),
              ),
            ),
            BotaoTexto(
              texto: 'Trocar',
              onTap: () async {
                final nova = await getDirectoryPath(
                  initialDirectory: estado.pasta,
                  confirmButtonText: 'Usar esta pasta',
                );
                if (nova != null) estado.trocarPasta(nova);
              },
            ),
          ],
        ),
        if (estado.ajustes.pasta != null)
          Align(
            alignment: Alignment.centerLeft,
            child: BotaoTexto(
              texto: 'Voltar para Downloads',
              onTap: () => estado.trocarPasta(null),
            ),
          ),
        const SizedBox(height: 22),
        _Titulo('Arrumação automática'),
        _Linha(
          texto: 'Todo dia',
          detalhe: 'PC desligado no horário? Arruma quando ligar.',
          fim: Switch(
            value: a.ativo,
            activeThumbColor: c.sobreMenta,
            activeTrackColor: c.menta,
            onChanged: (v) => estado.trocarAgendamento(a.copyWith(ativo: v)),
          ),
        ),
        AnimatedSize(
          duration: Mov.base,
          curve: Mov.saida,
          alignment: Alignment.topCenter,
          child: !a.ativo
              ? const SizedBox(width: double.infinity)
              : Column(
                  children: [
                    _Linha(
                      texto: 'Horário',
                      fim: _Horario(
                        agenda: a,
                        aoTrocar: (h, m) => estado.trocarAgendamento(
                          a.copyWith(hora: h, minuto: m),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        _Linha(
          texto: 'Ao ligar o PC',
          detalhe: 'Uns minutos depois de entrar, se tiver algo solto.',
          fim: Switch(
            value: a.aoLigar,
            activeThumbColor: c.sobreMenta,
            activeTrackColor: c.menta,
            onChanged: (v) => estado.trocarAgendamento(a.copyWith(aoLigar: v)),
          ),
        ),
        AnimatedSize(
          duration: Mov.base,
          curve: Mov.saida,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: Mov.base,
            switchInCurve: Mov.saida,
            transitionBuilder: (w, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, -.08),
                  end: Offset.zero,
                ).animate(anim),
                child: w,
              ),
            ),
            child: !a.algum
                ? const SizedBox(width: double.infinity)
                : Column(
                    key: const ValueKey('modo'),
                    children: [
                      _Linha(
                        texto: 'Modo',
                        fim: _Segmentos(
                          valor: a.modo,
                          aoTrocar: (m) =>
                              estado.trocarAgendamento(a.copyWith(modo: m)),
                        ),
                      ),
                      if (a.modo == Modo.claude && !claude)
                        _Nota(
                          'Sem o Claude Code instalado, a arrumação automática usa o Script.',
                          cor: c.aviso,
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 22),
        _Titulo('Claude'),
        _Linha(
          texto: claude
              ? 'Claude Code encontrado'
              : 'Claude Code não encontrado',
          detalhe: claude
              ? 'Usa a sua assinatura, com o Haiku 5.5.'
              : 'Instale pelo site claude.com/claude-code e entre com sua conta.',
          inicio: Icon(
            claude ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 18,
            color: claude ? c.mentaTinta : c.aviso,
          ),
        ),
        _Nota(
          'Senhas, chaves e .env nunca saem do lugar nem são enviados ao Claude.',
        ),
        const SizedBox(height: 22),
        _Titulo('Versão'),
        _Linha(
          texto: 'Neatly $versaoNeatly',
          detalhe: estado.atualizacao == null
              ? 'Atualiza sozinho quando sai versão nova.'
              : 'Versão ${estado.atualizacao!.versao} disponível.',
          fim: estado.atualizacao == null
              ? null
              : BotaoTexto(
                  texto: 'Atualizar',
                  cor: c.mentaTinta,
                  onTap: estado.atualizar,
                ),
        ),
      ],
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: c.fraca,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.texto, this.detalhe, this.inicio, this.fim});

  final String texto;
  final String? detalhe;
  final Widget? inicio;
  final Widget? fim;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (inicio != null) ...[inicio!, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(texto, style: TextStyle(fontSize: 14, color: c.tinta)),
                if (detalhe != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      detalhe!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.suave,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ?fim,
        ],
      ),
    );
  }
}

class _Nota extends StatelessWidget {
  const _Nota(this.texto, {this.cor});

  final String texto;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        texto,
        style: TextStyle(fontSize: 12.5, color: cor ?? c.fraca, height: 1.35),
      ),
    );
  }
}

/// Hora e minuto com setinhas (passo de 15 minutos).
class _Horario extends StatelessWidget {
  const _Horario({required this.agenda, required this.aoTrocar});

  final Agendamento agenda;
  final void Function(int hora, int minuto) aoTrocar;

  void _somar(int minutos) {
    final total = (agenda.hora * 60 + agenda.minuto + minutos) % (24 * 60);
    aoTrocar(total ~/ 60, total % 60);
  }

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.linha),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BotaoIcone(
            icone: Icons.remove_rounded,
            dica: '15 minutos antes',
            tamanho: 16,
            onTap: () => _somar(-15),
          ),
          AnimatedSwitcher(
            duration: Mov.rapido,
            transitionBuilder: (w, a) => FadeTransition(opacity: a, child: w),
            child: Text(
              agenda.horario,
              key: ValueKey(agenda.horario),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.tinta,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          BotaoIcone(
            icone: Icons.add_rounded,
            dica: '15 minutos depois',
            tamanho: 16,
            onTap: () => _somar(15),
          ),
        ],
      ),
    );
  }
}

/// Claude | Script, com o fundo deslizando até a opção escolhida.
class _Segmentos extends StatelessWidget {
  const _Segmentos({required this.valor, required this.aoTrocar});

  final Modo valor;
  final ValueChanged<Modo> aoTrocar;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    const largura = 76.0;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.tinta.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: Mov.base,
            curve: Mov.meio,
            left: valor == Modo.claude ? 0 : largura,
            top: 0,
            bottom: 0,
            width: largura,
            child: Container(
              decoration: BoxDecoration(
                color: c.elevada,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in Modo.values)
                GestureDetector(
                  onTap: () => aoTrocar(m),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SizedBox(
                      width: largura,
                      height: 28,
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: Mov.rapido,
                          style: TextStyle(
                            fontFamily: fonteTexto,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: m == valor ? c.tinta : c.suave,
                          ),
                          child: Text(nomeModo(m)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
