/// Nomes que o Windows não aceita como pasta.
const _reservados = {
  'con', 'prn', 'aux', 'nul', //
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

const profundidadeMaxima = 3;
const _tamanhoMaximo = 60;

/// Limpa uma pasta relativa vinda de fora (do Claude): nada de `..`, de
/// caminho absoluto, de caractere proibido ou de nome reservado. Devolve
/// null quando não sobra nada usável.
String? limparDestino(String bruto) {
  final partes = <String>[];
  for (var parte in bruto.split(RegExp(r'[\\/]+'))) {
    parte = parte
        .replaceAll(RegExp(r'[<>:"|?*\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // O Windows corta ponto e espaço do fim; melhor cortar antes.
    parte = parte.replaceAll(RegExp(r'[. ]+$'), '');
    if (parte.isEmpty || parte == '.' || parte == '..') continue;
    if (_reservados.contains(parte.toLowerCase())) parte = '_$parte';
    if (parte.length > _tamanhoMaximo) {
      parte = parte.substring(0, _tamanhoMaximo).trimRight();
    }
    partes.add(parte);
    if (partes.length == profundidadeMaxima) break;
  }
  return partes.isEmpty ? null : partes.join('/');
}
