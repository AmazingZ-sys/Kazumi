import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/plugin/tvbox_import_parser.dart';

void main() {
  final path = Platform.environment['TVBOX_GENERATED_CONFIG'];
  test(
    'generated source API config imports every published site without warnings',
    () {
      final input = File(path!).readAsStringSync();
      final document = jsonDecode(input) as Map<String, dynamic>;
      final sites = document['sites'] as List;
      expect(sites, isNotEmpty);
      // No baseUrl: generated URLs must be absolute to survive local snapshots.
      final imported = TvBoxImportParser.parse(input);
      expect(imported.warnings, isEmpty);
      expect(imported.plugins, hasLength(sites.length));
      expect(
        imported.plugins.map((plugin) => plugin.tvBoxSite!.key).toSet(),
        hasLength(sites.length),
      );
      for (var index = 0; index < sites.length; index++) {
        final site = imported.plugins[index].tvBoxSite!;
        expect(site.api, sites[index]['api']);
        expect(site.ext, sites[index]['ext']);
        expect(site.type, isIn([0, 1, 2, 4]));
      }
    },
    skip: path == null
        ? 'Set TVBOX_GENERATED_CONFIG to a generated kazumi.json'
        : false,
  );
}
