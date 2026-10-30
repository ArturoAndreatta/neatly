import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:neatly_core/neatly_core.dart';
import 'package:path/path.dart' as p;

/// Em que ponto a tela principal está.
enum Fase { inicio, planejando, previa, movendo }

/// Estado do app: ajustes, o que está solto, o plano e o histórico.
class Estado extends ChangeNotifier {
  Estado({required this.dados, String? downloads})
    : _downloads = downloads ?? pastaDownloads(),
      historico = Historico(dados) {
    ajustes = migrarV1(dados) ?? Ajustes.carregar(dados);
    // Migrado do Neatly 1: a tarefa antiga aponta para o PowerShell.
    if (!Ajustes.arquivo(dados).existsSync()) ajustes.salvar(dados);
    if (_mexeNoWindows) unawaited(_garantirTarefa());
    rodadas = historico.carregar();
    olhar();
    _vigia = Timer.periodic(const Duration(seconds: 4), (_) => olhar());
  }

  final String dados;
  final String _downloads;

  /// Só o app instalado mexe no Agendador. Em debug ou com dados de teste a
  /// tarefa apontaria para o build de desenvolvimento.
  static bool get _mexeNoWindows =>
      kReleaseMode && !Platform.environment.containsKey('NEATLY_DADOS');

  /// Regrava a tarefa apontando para este exe (muda a cada atualização).
  /// Logo depois de instalar o Windows às vezes recusa (antivírus ainda
  /// analisando o exe novo): tenta de novo algumas vezes.
  Future<void> _garantirTarefa() async {
    for (final espera in const [1, 5, 20, 60]) {
      await Future<void>.delayed(Duration(seconds: espera));
      if (aplicarAgendamento(ajustes.agendamento)) return;
    }
  }

  final Historico historico;
  late Ajustes ajustes;
  late Timer _vigia;

  Fase fase = Fase.inicio;
  Varredura varredura = const Varredura(soltos: [], recentes: 0);
  Plano? plano;
  List<Rodada> rodadas = [];

  /// Por que uma reorganização não trouxe nada (ex.: Claude fora do ar).
  String? aviso;

  /// Última rodada desta sessão (para o aviso com Desfazer).
  Rodada? ultima;
  Atualizacao? atualizacao;
  double? baixando;
  int _geracao = 0;

  String get pasta => ajustes.pasta ?? _downloads;
  String get nomePasta => p.basename(pasta);
  bool get claudeInstalado => acharClaude() != null;

  /// Claude Code e conta vinculada; null até a primeira consulta voltar.
  ContaClaude? conta;
  Timer? _esperaConta;

  /// Dá para usar o modo Claude. Antes da consulta, basta estar instalado.
  bool get claudePronto => conta?.pronta ?? claudeInstalado;

  /// O que falta para o modo Claude; null quando já dá.
  String? get faltaClaude => claudePronto
      ? null
      : (conta ?? const ContaClaude(SituacaoClaude.ausente)).falta;

  /// Esperando a pessoa terminar o login (ou a instalação) na outra janela.
  bool get vinculando => _esperaConta?.isActive ?? false;

  Future<void> verificarClaude() async {
    final nova = await consultarContaClaude();
    final mudou =
        nova.situacao != conta?.situacao || nova.email != conta?.email;
    conta = nova;
    if (nova.pronta && vinculando) {
      _esperaConta?.cancel();
      if (aviso != null && ajustes.modo == Modo.claude) aviso = null;
    } else if (!mudou) {
      return;
    }
    notifyListeners();
  }

  /// Abre o login do Claude Code (ou o instalador, se faltar) numa janela
  /// à parte e confere a conta a cada 3 segundos, por até 10 minutos.
  Future<void> vincularClaude() async {
    if (claudeInstalado) {
      await abrirLoginClaude();
    } else {
      await abrirInstalacaoClaude();
    }
    _esperaConta?.cancel();
    var vezes = 0;
    _esperaConta = Timer.periodic(const Duration(seconds: 3), (t) {
      if (++vezes >= 200) {
        t.cancel();
        notifyListeners();
      }
      unawaited(verificarClaude());
    });
    notifyListeners();
  }

  void pararVinculo() {
    _esperaConta?.cancel();
    notifyListeners();
  }

  void olhar() {
    if (fase != Fase.inicio) return;
    final v = varrer(pasta, ajustes);
    final mudou =
        v.recentes != varredura.recentes ||
        v.soltos.length != varredura.soltos.length ||
        !listEquals(
          [for (final a in v.soltos) a.caminho],
          [for (final a in varredura.soltos) a.caminho],
        );
    varredura = v;
    if (mudou) notifyListeners();
  }

  void trocarModo(Modo m) {
    ajustes = ajustes.copyWith(modo: m);
    ajustes.salvar(dados);
    notifyListeners();
  }

  void trocarTema(Tema t) {
    ajustes = ajustes.copyWith(tema: t);
    ajustes.salvar(dados);
    notifyListeners();
  }

  void trocarPasta(String? nova) {
    ajustes = Ajustes(
      pasta: nova,
      modo: ajustes.modo,
      agendamento: ajustes.agendamento,
      minutosRecentes: ajustes.minutosRecentes,
      ignorar: ajustes.ignorar,
      tema: ajustes.tema,
      regras: ajustes.regras,
    );
    ajustes.salvar(dados);
    varredura = const Varredura(soltos: [], recentes: 0);
    olhar();
    notifyListeners();
  }

  /// Devolve false se o Windows recusar a tarefa.
  bool trocarAgendamento(Agendamento a) {
    final ok = !_mexeNoWindows || aplicarAgendamento(a);
    if (ok) {
      ajustes = ajustes.copyWith(agendamento: a);
      ajustes.salvar(dados);
    }
    notifyListeners();
    return ok;
  }

  /// Regras de gosto em uso (as da pessoa ou as de fábrica).
  String get regras => regrasOuPadrao(ajustes.regras);

  /// Troca as regras de gosto. Regras novas passam antes por um teste a
  /// seco; se não servirem, nada é salvo e volta o motivo.
  Future<String?> salvarRegras(String? novas) async {
    final limpas = novas == null || novas.trim().isEmpty ? null : novas.trim();
    final padrao = limpas == null || limpas == regrasPadrao.trim();
    if (!padrao) {
      final erro = await PlanejadorClaude(regras: limpas).testarRegras();
      if (erro != null) return erro;
    }
    ajustes = ajustes.comRegras(padrao ? null : limpas);
    ajustes.salvar(dados);
    notifyListeners();
    return null;
  }

  /// Replanejando a prévia com um pedido da pessoa.
  bool ajustando = false;

  /// Por que o último ajuste não deu certo.
  String? erroAjuste;

  /// Pedido aplicado por último, que ainda pode virar regra.
  String? pedidoAplicado;

  Future<void> ajustar(String pedido) async {
    final pl = plano;
    if (pl == null || ajustando || pedido.trim().isEmpty) return;
    final g = _geracao;
    ajustando = true;
    erroAjuste = null;
    pedidoAplicado = null;
    notifyListeners();
    try {
      final novo = await ajustarPlano(pl, pedido, ajustes);
      if (g != _geracao) return;
      plano = novo;
      pedidoAplicado = pedido.trim();
    } on ErroClaude catch (e) {
      if (g != _geracao) return;
      erroAjuste = e.mensagem;
    }
    ajustando = false;
    notifyListeners();
  }

  /// Acrescenta [pedidoAplicado] às regras de gosto, como uma regra a mais.
  void guardarPedido() {
    final pedido = pedidoAplicado;
    if (pedido == null) return;
    final frase = pedido.endsWith('.') ? pedido : '$pedido.';
    ajustes = ajustes.comRegras('$regras\n- $frase');
    ajustes.salvar(dados);
    pedidoAplicado = null;
    notifyListeners();
  }

  void esquecerPedido() {
    if (pedidoAplicado == null) return;
    pedidoAplicado = null;
    notifyListeners();
  }

  void _limparAjuste() {
    ajustando = false;
    erroAjuste = null;
    pedidoAplicado = null;
  }

  /// Rodada atual é a reorganização da pasta toda.
  bool reorganizando = false;

  Future<void> organizar({bool tudo = false}) async {
    final g = ++_geracao;
    fase = Fase.planejando;
    reorganizando = tudo;
    aviso = null;
    _limparAjuste();
    notifyListeners();
    final inicio = DateTime.now();
    final novo = tudo
        ? await montarReorganizacao(pasta, ajustes)
        : await montarPlano(pasta, ajustes, ajustes.modo, rodadas: rodadas);
    // O Script responde na hora; um respiro curto evita a tela piscar.
    final faltam =
        const Duration(milliseconds: 450) - DateTime.now().difference(inicio);
    if (faltam > Duration.zero) await Future<void>.delayed(faltam);
    if (g != _geracao) return;
    if (novo.vazio) {
      fase = Fase.inicio;
      reorganizando = false;
      aviso = novo.aviso;
      // Talvez a conta tenha saído: atualiza o que Ajustes mostra.
      if (aviso != null && conta != null) unawaited(verificarClaude());
      olhar();
    } else {
      plano = novo;
      fase = Fase.previa;
    }
    notifyListeners();
  }

  void cancelar() {
    _geracao++;
    _limparAjuste();
    fase = Fase.inicio;
    reorganizando = false;
    plano = null;
    olhar();
    notifyListeners();
  }

  Future<void> mover() async {
    final pl = plano;
    if (pl == null || ajustando) return;
    _limparAjuste();
    fase = Fase.movendo;
    notifyListeners();
    final r = await Future(() => aplicar(pl, historico));
    // Dá tempo da pilha entrar na pasta antes de voltar ao início.
    await Future<void>.delayed(const Duration(milliseconds: 650));
    ultima = r.mudancas.isEmpty ? null : r;
    rodadas = historico.carregar();
    plano = null;
    fase = Fase.inicio;
    reorganizando = false;
    varredura = const Varredura(soltos: [], recentes: 0);
    olhar();
    notifyListeners();
  }

  int desfazerRodada(Rodada r) {
    final n = desfazer(r, historico);
    if (identical(r, ultima) || r.id == ultima?.id) ultima = null;
    rodadas = historico.carregar();
    olhar();
    notifyListeners();
    return n;
  }

  void esquecerUltima() {
    if (ultima == null) return;
    ultima = null;
    notifyListeners();
  }

  void abrirPasta([String? alvo]) {
    final caminho = alvo ?? pasta;
    if (File(caminho).existsSync()) {
      Process.start('explorer.exe', ['/select,', caminho]);
    } else {
      Process.start('explorer.exe', [caminho]);
    }
  }

  Future<void> procurarAtualizacao() async {
    atualizacao = await procurarAtualizacaoNoGitHub();
    notifyListeners();
  }

  Future<void> atualizar() async {
    final a = atualizacao;
    if (a == null || baixando != null) return;
    baixando = 0;
    notifyListeners();
    try {
      await instalarAtualizacao(
        a,
        progresso: (x) {
          baixando = x;
          notifyListeners();
        },
      );
      exit(0);
    } on Object {
      baixando = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _vigia.cancel();
    _esperaConta?.cancel();
    super.dispose();
  }
}

/// Atalho para os testes trocarem a consulta.
@visibleForTesting
Future<Atualizacao?> Function() procurarAtualizacaoNoGitHub =
    procurarAtualizacao;

/// Atalho para os testes trocarem a consulta da conta.
@visibleForTesting
Future<ContaClaude> Function() consultarContaClaude = verificarContaClaude;
