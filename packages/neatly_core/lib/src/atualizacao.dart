import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Versão deste build (igual à do pubspec do app e à tag do release).
const versaoNeatly = '2.1.0';

const _repo = 'ArturoAndreatta/neatly';
const _instalador = 'NeatlySetup.exe';

/// Release mais novo que o instalado.
class Atualizacao {
  const Atualizacao(this.versao, this.url);

  final String versao;
  final String url;
}

/// "2.1.0" > "2.0.9". Ignora sufixos.
int compararVersoes(String a, String b) {
  List<int> partes(String v) => [
    for (final x
        in v.replaceFirst(RegExp('^v'), '').split(RegExp(r'[.+-]')).take(3))
      int.tryParse(x) ?? 0,
  ];
  final pa = partes(a), pb = partes(b);
  for (var i = 0; i < 3; i++) {
    final x = (i < pa.length ? pa[i] : 0) - (i < pb.length ? pb[i] : 0);
    if (x != 0) return x.sign;
  }
  return 0;
}

/// Consulta o último release no GitHub. Sem rede ou sem novidade: null.
Future<Atualizacao?> procurarAtualizacao({String atual = versaoNeatly}) async {
  final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await cliente.getUrl(
      Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
    );
    req.headers
      ..set('User-Agent', 'neatly')
      ..set('Accept', 'application/vnd.github+json');
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
    final tag = j['tag_name'] as String? ?? '';
    if (compararVersoes(tag, atual) <= 0) return null;
    for (final a in (j['assets'] as List? ?? const [])) {
      if (a is Map && a['name'] == _instalador) {
        return Atualizacao(
          tag.replaceFirst('v', ''),
          a['browser_download_url'] as String,
        );
      }
    }
    return null;
  } on Object {
    return null;
  } finally {
    cliente.close(force: true);
  }
}

/// Baixa o instalador e roda em silêncio; ele fecha o Neatly, troca os
/// arquivos e abre de novo. Quem chama deve sair do app logo depois.
Future<void> instalarAtualizacao(
  Atualizacao a, {
  void Function(double)? progresso,
}) async {
  final destino = File(p.join(Directory.systemTemp.path, _instalador));
  final cliente = HttpClient();
  try {
    final res = await (await cliente.getUrl(Uri.parse(a.url))).close();
    if (res.statusCode != 200) {
      throw HttpException('Download falhou (${res.statusCode})');
    }
    final total = res.contentLength;
    var recebido = 0;
    final saida = destino.openWrite();
    await for (final bloco in res) {
      saida.add(bloco);
      recebido += bloco.length;
      if (total > 0) progresso?.call(recebido / total);
    }
    await saida.close();
  } finally {
    cliente.close();
  }
  await Process.start(destino.path, [
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/CLOSEAPPLICATIONS',
  ], mode: ProcessStartMode.detached);
}
