import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:neatly_core/neatly_core.dart';

import '../estado.dart';
import '../tema.dart';
import 'barra.dart';
import 'comum.dart';

String _nomeTema(Tema t) => switch (t) {
  Tema.sistema => 'Sistema',
  Tema.claro => 'Claro',
  Tema.escuro => 'Escuro',
};

/// Conteúdo da gaveta de ajustes: pasta, arrumação, aparência e versão.
class ConteudoAjustes extends StatelessWidget {
  const ConteudoAjustes({super.key, required this.estado});

  final Estado estado;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final a = estado.ajustes.agendamento;
    final claude = estado.claudePronto;

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
                          opcoes: Modo.values,
                          valor: a.modo,
                          nome: nomeModo,
                          aoTrocar: (m) =>
                              estado.trocarAgendamento(a.copyWith(modo: m)),
                        ),
                      ),
                      if (a.modo == Modo.claude && !claude)
                        _Nota(
                          'Sem a conta do Claude vinculada, a arrumação automática usa o Script.',
                          cor: c.aviso,
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 22),
        _Titulo('Aparência'),
        _Linha(
          texto: 'Tema',
          fim: _Segmentos(
            opcoes: Tema.values,
            valor: estado.ajustes.tema,
            nome: _nomeTema,
            largura: 70,
            aoTrocar: estado.trocarTema,
          ),
        ),
        const SizedBox(height: 22),
        _Titulo('Claude'),
        _ContaClaude(estado: estado),
        _Nota(
          'Senhas, chaves e .env nunca saem do lugar nem são enviados ao Claude.',
        ),
        if (claude) ...[
          const SizedBox(height: 22),
          _Titulo('Seu jeito de organizar'),
          _Regras(estado: estado),
        ],
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

/// Situação do Claude Code e da conta, com o botão para vincular.
class _ContaClaude extends StatelessWidget {
  const _ContaClaude({required this.estado});

  final Estado estado;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
    final conta = estado.conta;
    final situacao =
        conta?.situacao ??
        (estado.claudeInstalado
            ? SituacaoClaude.conectado
            : SituacaoClaude.ausente);
    final esperando = estado.vinculando && situacao != SituacaoClaude.conectado;

    final (texto, detalhe) = switch (situacao) {
      SituacaoClaude.conectado => (
        'Conta do Claude vinculada',
        conta?.email == null
            ? 'Usa a sua assinatura, com o Haiku 5.5.'
            : '${conta!.email} · Haiku 5.5',
      ),
      SituacaoClaude.semConta => (
        'Nenhuma conta do Claude vinculada',
        esperando
            ? 'Termine o login no navegador. Aqui atualiza sozinho.'
            : 'Entre com uma conta Pro, Max, Team ou Enterprise.',
      ),
      SituacaoClaude.ausente => (
        'Claude Code não instalado',
        esperando
            ? 'Siga a janela que abriu. Depois é só entrar com a conta.'
            : 'O modo Claude usa o Claude Code. A instalação leva um minuto.',
      ),
    };

    final Widget fim = esperando
        ? Row(
            key: const ValueKey('esperando'),
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.menta,
                ),
              ),
              BotaoTexto(texto: 'Parar', onTap: estado.pararVinculo),
            ],
          )
        : switch (situacao) {
            SituacaoClaude.conectado => const SizedBox.shrink(
              key: ValueKey('ok'),
            ),
            SituacaoClaude.semConta => BotaoTexto(
              key: const ValueKey('vincular'),
              texto: 'Vincular conta',
              cor: c.mentaTinta,
              onTap: estado.vincularClaude,
            ),
            SituacaoClaude.ausente => BotaoTexto(
              key: const ValueKey('instalar'),
              texto: 'Instalar',
              cor: c.mentaTinta,
              onTap: estado.vincularClaude,
            ),
          };

    final ok = situacao == SituacaoClaude.conectado;
    return _Linha(
      texto: texto,
      detalhe: detalhe,
      inicio: AnimatedSwitcher(
        duration: Mov.rapido,
        transitionBuilder: (w, a) => ScaleTransition(
          scale: Tween(begin: .6, end: 1.0).animate(a),
          child: FadeTransition(opacity: a, child: w),
        ),
        child: Icon(
          ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          key: ValueKey(ok),
          size: 18,
          color: ok ? c.mentaTinta : c.aviso,
        ),
      ),
      fim: AnimatedSwitcher(
        duration: Mov.rapido,
        transitionBuilder: (w, a) => FadeTransition(opacity: a, child: w),
        child: fim,
      ),
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

/// Claude | Script (ou Sistema | Claro | Escuro), com o fundo deslizando
/// até a opção escolhida.
class _Segmentos<T> extends StatelessWidget {
  const _Segmentos({
    required this.opcoes,
    required this.valor,
    required this.nome,
    required this.aoTrocar,
    this.largura = 76,
  });

  final List<T> opcoes;
  final T valor;
  final String Function(T) nome;
  final ValueChanged<T> aoTrocar;
  final double largura;

  @override
  Widget build(BuildContext context) {
    final c = Cores.de(context);
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
            left: opcoes.indexOf(valor) * largura,
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
              for (final m in opcoes)
                Semantics(
                  button: true,
                  selected: m == valor,
                  child: GestureDetector(
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
                            child: Text(nome(m)),
                          ),
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

/// Regras de gosto que o Claude segue, editáveis. Antes de salvar, o
/// Claude testa a seco: regra que quebra a resposta não entra.
class _Regras extends StatefulWidget {
  const _Regras({required this.estado});

  final Estado estado;

  @override
  State<_Regras> createState() => _RegrasState();
}

enum _Salvando { nada, testando, salvo }

class _RegrasState extends State<_Regras> {
  late final _texto = TextEditingController(text: widget.estado.regras);
  final _foco = FocusNode();
  late String _base = widget.estado.regras;
  _Salvando _salvando = _Salvando.nada;
  String? _erro;
  Timer? _apagar;

  @override
  void initState() {
    super.initState();
    _texto.addListener(_mudou);
    _foco.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant _Regras old) {
    super.didUpdateWidget(old);
    _sincronizar();
  }

  /// Regra guardada pela prévia: entra na caixa se não houver edição.
  void _sincronizar() {
    final atual = widget.estado.regras;
    if (atual == _base) return;
    final semEdicao = _texto.text.trim() == _base.trim();
    _base = atual;
    if (semEdicao) _texto.text = atual;
  }

  void _mudou() {
    if (_erro != null || _salvando == _Salvando.salvo) {
      _apagar?.cancel();
      _erro = null;
      _salvando = _Salvando.nada;
    }
    if (mounted) setState(() {});
  }

  bool get _editado => _texto.text.trim() != _base.trim();
  bool get _ehPadrao => _texto.text.trim() == regrasPadrao.trim();

  Future<void> _salvar([String? texto]) async {
    if (_salvando == _Salvando.testando) return;
    setState(() {
      _salvando = _Salvando.testando;
      _erro = null;
    });
    final erro = await widget.estado.salvarRegras(texto ?? _texto.text);
    if (!mounted) return;
    if (erro == null) {
      _base = widget.estado.regras;
      if (texto != null) _texto.text = _base;
    }
    setState(() {
      _erro = erro;
      _salvando = erro == null ? _Salvando.salvo : _Salvando.nada;
    });
    if (erro == null) {
      _apagar?.cancel();
      _apagar = Timer(const Duration(milliseconds: 1800), () {
        if (mounted) setState(() => _salvando = _Salvando.nada);
      });
    }
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
    final testando = _salvando == _Salvando.testando;
    final Widget acao = switch (_salvando) {
      _Salvando.testando => Row(
        key: const ValueKey('testando'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.menta),
          ),
          const SizedBox(width: 8),
          Text(
            'Testando as regras',
            style: TextStyle(fontSize: 13, color: c.suave),
          ),
        ],
      ),
      _Salvando.salvo => Row(
        key: const ValueKey('salvo'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 16, color: c.mentaTinta),
          const SizedBox(width: 6),
          Text('Salvo', style: TextStyle(fontSize: 13, color: c.mentaTinta)),
        ],
      ),
      _Salvando.nada when _editado => BotaoPrincipal(
        key: const ValueKey('salvar'),
        texto: 'Salvar',
        onTap: _salvar,
      ),
      _Salvando.nada => const SizedBox(key: ValueKey('nada'), height: 38),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'O Claude segue estas regras ao organizar, inclusive na arrumação '
          'automática. Uma por linha.',
          style: TextStyle(fontSize: 12.5, color: c.suave, height: 1.35),
        ),
        const SizedBox(height: 10),
        AnimatedContainer(
          duration: Mov.rapido,
          curve: Curves.ease,
          decoration: BoxDecoration(
            color: c.superficie,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _erro != null
                  ? c.aviso
                  : _foco.hasFocus
                  ? c.menta
                  : c.linha,
              width: _foco.hasFocus ? 1.5 : 1,
            ),
          ),
          child: AnimatedOpacity(
            duration: Mov.rapido,
            opacity: testando ? .55 : 1,
            child: TextField(
              controller: _texto,
              focusNode: _foco,
              readOnly: testando,
              minLines: 6,
              maxLines: 14,
              maxLength: 4000,
              buildCounter:
                  (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
              cursorColor: c.menta,
              style: TextStyle(fontSize: 13, color: c.tinta, height: 1.45),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(12, 10, 12, 10),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: Mov.base,
          curve: Mov.saida,
          alignment: Alignment.topCenter,
          child: _erro == null
              ? const SizedBox(width: double.infinity)
              : Entrada(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
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
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: c.aviso,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$_erro Nada foi salvo.',
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
                ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            AnimatedOpacity(
              duration: Mov.rapido,
              opacity: _ehPadrao ? 0 : 1,
              child: IgnorePointer(
                ignoring: _ehPadrao || testando,
                child: BotaoTexto(
                  texto: 'Restaurar padrão',
                  icone: Icons.restart_alt_rounded,
                  onTap: () => _salvar(''),
                ),
              ),
            ),
            const Spacer(),
            AnimatedSwitcher(
              duration: Mov.rapido,
              switchInCurve: Mov.saida,
              transitionBuilder: (w, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(
                  scale: Tween(begin: .96, end: 1.0).animate(a),
                  alignment: Alignment.centerRight,
                  child: w,
                ),
              ),
              child: acao,
            ),
          ],
        ),
      ],
    );
  }
}
