import 'ajustes.dart';
import 'arquivo.dart';

/// Um arquivo e a pasta (relativa à raiz, com `/`) para onde ele vai.
class Movimento {
  const Movimento(this.arquivo, this.destino);

  final ArquivoSolto arquivo;

  /// Ex.: `Faculdade/Cálculo II`. Para pasta inteira é o caminho final da
  /// própria pasta, já com o nome novo (`Minecraft/Plugins`).
  final String destino;

  /// Pasta que muda de nome: vira [destino] (ou junta o conteúdo nele, se
  /// já existir) em vez de entrar nele.
  bool get renomeia => arquivo.pasta && destino.split('/').last != arquivo.nome;
}

/// Pasta da prévia, com subpastas e arquivos.
class NoPasta {
  NoPasta(this.nome, {this.nova = false});

  final String nome;

  /// Ainda não existe no disco.
  bool nova;
  final Map<String, NoPasta> filhas = {};
  final List<ArquivoSolto> arquivos = [];

  /// Pastas soltas que viram esta (ou juntam o conteúdo nela).
  final List<ArquivoSolto> juntadas = [];

  int get total =>
      arquivos.length +
      juntadas.length +
      filhas.values.fold(0, (s, f) => s + f.total);
}

/// O que uma rodada vai fazer, antes de mexer em qualquer coisa.
class Plano {
  Plano({
    required this.raiz,
    required this.modo,
    required this.movimentos,
    this.aviso,
    this.limpar = const [],
  });

  final String raiz;

  /// Modo que de fato montou o plano (Claude pode cair para script).
  final Modo modo;
  final List<Movimento> movimentos;

  /// Algo que o usuário precisa saber (ex.: Claude indisponível).
  final String? aviso;

  /// Pastas de organização esvaziadas pela reorganização: saem se ficarem
  /// vazias depois de mover.
  final List<String> limpar;

  bool get vazio => movimentos.isEmpty;

  /// Árvore para a prévia; [existe] diz se a pasta relativa já existe.
  List<NoPasta> arvore(bool Function(String relativa) existe) {
    final raizes = <String, NoPasta>{};
    for (final m in movimentos) {
      final partes = m.destino.split('/');
      // Pasta que mantém o nome aparece dentro da pasta mãe, como arquivo.
      if (m.arquivo.pasta && !m.renomeia) partes.removeLast();
      var nivel = raizes;
      NoPasta? atual;
      var rel = '';
      for (final parte in partes) {
        rel = rel.isEmpty ? parte : '$rel/$parte';
        final r = rel;
        atual = nivel.putIfAbsent(
          parte,
          () => NoPasta(parte, nova: !existe(r)),
        );
        nivel = atual.filhas;
      }
      (m.renomeia ? atual!.juntadas : atual!.arquivos).add(m.arquivo);
    }
    final lista = raizes.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return lista;
  }
}
