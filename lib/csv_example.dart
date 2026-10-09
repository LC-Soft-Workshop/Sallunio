import 'dart:convert';
import 'dart:io';

// UTF-8 BOM and CRLF help French spreadsheet applications preserve accents.
const exampleCsv =
    '\uFEFFréférent;effectif;repas;mobilité;allergies\r\n'
    'Camille fictif;12;Normal;;\r\n'
    'Morgan fictif;4;Végétarien;Fauteuil;"Exemple : noix; lait"\r\n'
    'Alex fictif;3;Ne mange pas;Autre mobilité;\r\n'
    'Jordan fictif;1;Sans gluten;;\r\n'
    'René fictif;2;;;\r\n';

Future<void> saveExampleCsv(String path) =>
    File(path).writeAsBytes(utf8.encode(exampleCsv)).then((_) {});
