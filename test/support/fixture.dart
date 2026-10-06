import 'package:quickdex/data/models.dart';

const _allNormal = {
  'normal': 1.0,
  'fire': 1.0,
  'water': 1.0,
  'electric': 1.0,
  'grass': 1.0,
  'ice': 1.0,
  'fighting': 1.0,
  'poison': 1.0,
  'ground': 1.0,
  'flying': 1.0,
  'psychic': 1.0,
  'bug': 1.0,
  'rock': 1.0,
  'ghost': 1.0,
  'dragon': 1.0,
  'dark': 1.0,
  'steel': 1.0,
  'fairy': 1.0,
};

PokemonEntry fx(
  int id,
  String name, {
  String? form,
  List<String> types = const ['normal'],
  int? dex,
}) => PokemonEntry(
  id: id,
  dex: dex ?? id,
  name: name,
  species: form == null ? name : name.split(' (').first,
  form: form,
  types: types,
  stats: const [50, 50, 50, 50, 50, 50],
  forms: [id],
  chain: id,
  defense: _allNormal,
);

final fixtureEntries = [
  fx(25, 'Pikachu'),
  fx(26, 'Raichu'),
  fx(29, 'Nidoran♀'),
  fx(83, "Farfetch’d"),
  fx(122, 'Mr. Mime'),
  fx(150, 'Mewtwo'),
  fx(151, 'Mew'),
  fx(250, 'Ho-Oh'),
  fx(439, 'Mime Jr.'),
  fx(669, 'Flabébé'),
  fx(10100, 'Raichu (Alolan)', form: 'Alolan', dex: 26),
];
