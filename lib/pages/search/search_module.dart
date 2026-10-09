import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/search/image_search_page.dart';
import 'package:kazumi/pages/search/drama_search_page.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/pages/search/search_page.dart';
import 'package:kazumi/plugins/plugins_controller.dart';

void _provideSearchController(Scoped scoped) {
  scoped.add<SearchPageController>(SearchPageController.new);
}

final searchModule = createModule(
  path: '/search',
  register: (c) {
    c
      ..route(
        '/',
        provide: _provideSearchController,
        child: (context, state) => SearchPage(
          controller: context.read<SearchPageController>(),
        ),
      )
      ..route(
        '/image',
        provide: _provideSearchController,
        child: (context, state) => ImageSearchPage(
          controller: context.read<SearchPageController>(),
        ),
      )
      ..route(
        '/drama',
        child: (context, state) => DramaSearchPage(
          pluginsController: inject<PluginsController>(),
        ),
      )
      ..route(
        '/:tag',
        provide: _provideSearchController,
        child: (context, state) => SearchPage(
          controller: context.read<SearchPageController>(),
          inputTag: state['tag'] ?? '',
        ),
      );
  },
);
